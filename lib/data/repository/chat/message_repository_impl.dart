import 'dart:async';
import 'dart:math';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/data/local/chat/chat_dao.dart';
import 'package:nox_app/data/local/chat/message_dao.dart';
import 'package:nox_app/data/mapper/chat/message_mapper.dart';
import 'package:nox_app/data/mapper/chat/message_wire_mapper.dart';
import 'package:nox_app/data/remote/datasource/message_remote_data_source.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:nox_app/general/formatters/chat_preview_formatter.dart';
import 'package:nox_app/general/identity/identity_resolver.dart';
import 'package:nox_app/general/chat_seed_mock_data.dart';
import 'package:nox_app/general/identity_mock_data.dart';
import 'package:nox_app/general/mock_seq.dart';
import 'package:uuid/uuid.dart';

/// Cache-first chat thread (5.2) over the local Sembast DB. The [MessageRemoteDataSource]
/// (mock this phase) seeds a chat's history ONCE on first open; thereafter the
/// thread is paginated FROM the DB by the seq cursor (newest batch first, older
/// batches by `before_seq` — contract §5), and [sendMessage] persists the accepted
/// message locally. When the transport lands (027) and the binding flips (028),
/// only the data source swaps; the DB contract and the wire shapes stay.
@LazySingleton(as: MessageRepository, env: [Environment.dev, Environment.prod, Environment.test])
class MessageRepositoryImpl with BaseRepositoryHelper implements MessageRepository {
  MessageRepositoryImpl(
    this._messageDao,
    this._messageRemote,
    this._mapper,
    this._wireMapper,
    this._chatDao,
    this._sessionRepository,
    this._syncRepository,
  );

  final MessageDao _messageDao;
  final MessageRemoteDataSource _messageRemote;
  final MessageMapper _mapper;
  final MessageWireMapper _wireMapper;
  final ChatDao _chatDao;
  final SessionRepository _sessionRepository;
  final SyncRepository _syncRepository;

  static const Uuid _uuid = Uuid();

  /// One-time seed of a chat's deterministic mock history into the DB (empty chat).
  /// The mock seeds own rows with [IdentityMockData.fallbackOwnId]; they are reconciled
  /// to the signed-in identity here so own-detection follows the session (feature 015).
  /// Safe because the identifier is stable for the life of the local DB (logout wipes it).
  Future<void> _seedChatIfEmpty(String chatId) async {
    if (await _messageDao.countByChat(chatId) > 0) return;
    // Own rows seed ONCE and stick for the DB's life. A FAILED session read must not
    // bake them under the fallback id while a real session exists — that would mismatch
    // a thread whose currentId resolved from a good read (own history rendered as a
    // stranger, permanently). Defer seeding until the read succeeds; a genuine "no
    // session" still succeeds (data == null) → fallback id, which is correct.
    final sessionResult = await _sessionRepository.readSession();
    if (!sessionResult.hasData) return;
    final identity = resolveIdentity(sessionResult.data);
    final all = <MessageModel>[];
    int? beforeSeq;
    while (true) {
      // Walk the contract cursor backward: the tail first, then batches older
      // than the oldest received seq, until has_more says stop. A data==null
      // envelope throws → the enclosing execute() maps it to error.
      final response = await _messageRemote.getMessages(
        config: GetMessagesConfig(chatId: chatId, beforeSeq: beforeSeq, limit: GetMessagesConfig.pageSize),
      );
      final data = unwrapEnvelope(response, 'messages');
      final batch = _wireMapper.toListModel(entities: data.messages);
      all.insertAll(0, batch);
      if (!data.hasMore || batch.isEmpty) break;
      beforeSeq = batch.first.seq;
    }
    final reconciled = all.map((m) {
      if (m.authorId != IdentityMockData.fallbackOwnId) return m;
      // Own seed rows follow the signed-in identity and carry the local
      // "accepted by server" status (the wire has no statuses - §5).
      return m.copyWith(authorId: identity.id, authorLabel: identity.label, status: MessageStatus.sent);
    }).toList();
    // The genesis line is client-synthesized (contract §4: no system messages
    // on the wire): position 0 of the chat's seq range, rendered from the
    // seed persona - byte-identical to the pre-025 seeded line.
    final genesis = MessageModel(
      id: '${chatId}_sys',
      seq: reconciled.isEmpty ? 0 : reconciled.map((m) => m.seq).reduce(min) - 1,
      chatId: chatId,
      authorId: 'system',
      authorLabel: ChatSeedMockData.genesisAuthorLabel,
      isSystem: true,
      sentAt: AppClock.now().subtract(ChatSeedMockData.genesisAge),
    );
    await _messageDao.saveData([genesis, ...reconciled].map((m) => _mapper.toEntity(model: m)).toList());
    // The cursor's promise is "everything up to seq is applied locally"
    // (§9.4) - seeding applies the whole batch at once.
    if (reconciled.isNotEmpty) {
      await _syncRepository.advanceCursor(reconciled.map((m) => m.seq).reduce(max));
    }
  }

  /// Chats already checked for pre-025 rows this process (cheap memo — the
  /// backfill itself is one-time per DB).
  final Set<String> _legacySeqChecked = <String>{};

  /// One-time per-chat backfill for rows persisted before 025 (no `seq` field):
  /// assigns ascending synthetic seqs in stored (sentAt) order BELOW every real
  /// seq in the chat, so the value cursor in [getMessages] stays sound on an
  /// upgraded-in-place DB (a legacy `seq == 0` cursor would otherwise trim the
  /// whole window and strand the older history). Device-local numbering only —
  /// these rows never travel back to the wire.
  Future<void> _backfillLegacySeqIfNeeded(String chatId) async {
    if (!_legacySeqChecked.add(chatId)) return;
    final entities = await _messageDao.getByChatSorted(chatId);
    final legacy = entities.where((e) => e.seq == null).toList();
    if (legacy.isEmpty) return;
    final realSeqs = entities.map((e) => e.seq).whereType<int>();
    // The block lands directly below the chat's lowest real seq (or at 1..n on
    // an all-legacy chat), preserving the stored order.
    var next = realSeqs.isEmpty ? 1 : realSeqs.reduce(min) - legacy.length;
    await _messageDao.saveData([for (final e in legacy) e.copyWith(seq: next++)]);
  }

  @override
  Future<RepositoryResult<(List<MessageModel>, PageMetadata)>> getMessages({required GetMessagesConfig config}) {
    return execute<(List<MessageModel>, PageMetadata)>(() async {
      await _seedChatIfEmpty(config.chatId);
      await _backfillLegacySeqIfNeeded(config.chatId);
      final all = (await _messageDao.getByChatSorted(config.chatId)).map((e) => _mapper.toModel(entity: e)).toList();
      // Cursor window over the seq-ascending list: everything strictly older
      // than beforeSeq (or the whole list for the tail), newest `limit` rows.
      var end = all.length;
      final beforeSeq = config.beforeSeq;
      if (beforeSeq != null) {
        while (end > 0 && all[end - 1].seq >= beforeSeq) {
          end--;
        }
      }
      final start = (end - config.limit) < 0 ? 0 : end - config.limit;
      final slice = all.sublist(start, end);
      return RepositoryResult<(List<MessageModel>, PageMetadata)>.success(data: (slice, PageMetadata(hasMore: start > 0)));
    });
  }

  @override
  Stream<List<MessageModel>> watchMessages(String chatId) async* {
    await _seedChatIfEmpty(chatId);
    await _backfillLegacySeqIfNeeded(chatId);
    yield* _messageDao.watch(chatId).map((entities) => entities.map((e) => _mapper.toModel(entity: e)).toList());
  }

  @override
  Future<RepositoryResult<MessageModel>> sendMessage({
    required String chatId,
    required String clientMessageId,
    String? text,
    MessageAttachment? attachment,
  }) {
    return execute<MessageModel>(() async {
      // Unwrap the ResponseEntity<MessageWireEntity> echo envelope (P6 — uniform with the
      // paged reads); a failed envelope has null data → throw → execute() maps it to error.
      final response = await _messageRemote.sendMessage(
        chatId: chatId,
        clientMessageId: clientMessageId,
        text: text,
        attachment: attachment,
      );
      final data = unwrapEnvelope(response, 'send');
      // The wire carries no statuses (§5): an echoed own message is locally
      // "accepted by server".
      var message = _wireMapper.toModel(entity: data).copyWith(status: MessageStatus.sent);
      // The wire echo is the (future) backend contract — it carries NO device-local path.
      // Re-attach the client's localPath from the sent attachment so a sent image still
      // previews/saves (F4/F2): the server owns id/timestamp, the client owns the file path.
      final sentPath = attachment?.localPath;
      if (sentPath != null && message.attachment != null) {
        message = message.copyWith(attachment: message.attachment!.copyWith(localPath: sentPath));
      }
      await _messageDao.upsert(_mapper.toEntity(model: message));
      // Keep the chat row (list) consistent with the thread: update preview + time + order.
      // A failed send returns an error before reaching here, so the row is never touched (FR-004).
      await _touchChatRow(chatId, message, incrementUnread: false);
      await _syncRepository.advanceCursor(message.seq);
      return RepositoryResult<MessageModel>.success(data: message);
    });
  }

  @override
  Future<void> seedCreatedChat({required String chatId}) async {
    // Idempotent: only the genesis line, and only when the chat has no messages yet.
    if (await _messageDao.countByChat(chatId) > 0) return;
    // Don't bake the fallback label over a real session on a degraded read (mirrors
    // _seedChatIfEmpty): skip the genesis line best-effort — a genuine no-session still
    // succeeds (data == null → fallback label, which is correct).
    final sessionResult = await _sessionRepository.readSession();
    if (!sessionResult.hasData) return;
    final identity = resolveIdentity(sessionResult.data);
    final systemLine = MessageModel(
      id: '${chatId}_sys',
      seq: MockSeq.next(),
      chatId: chatId,
      authorId: 'system',
      authorLabel: identity.label, // renders "Chat created by {label}" via l10n.systemChatCreated
      sentAt: AppClock.now(),
      isSystem: true,
    );
    await _messageDao.upsert(_mapper.toEntity(model: systemLine));
  }

  @override
  Future<List<MessageAttachment>> chatFiles({required String chatId}) async {
    // Derive the 5.4 shared-files view from the chat's persisted attachments, newest-first
    // (feature 017). Seed first so the view is correct even if opened before the thread.
    await _seedChatIfEmpty(chatId);
    final messages = (await _messageDao.getByChatSorted(chatId)).map((e) => _mapper.toModel(entity: e)).toList();
    final files = <MessageAttachment>[];
    for (final message in messages.reversed) {
      final attachment = message.attachment;
      if (attachment != null) files.add(attachment);
    }
    return files;
  }

  @override
  Future<void> simulateIncoming({required String chatId}) async {
    // Debug stand-in for a server push: an inbound message (author != me) + unread bump.
    final message = MessageModel(
      id: 'sim_${_uuid.v4()}',
      seq: MockSeq.next(),
      chatId: chatId,
      authorId: 'other:$chatId',
      authorLabel: 'Someone',
      text: 'Simulated incoming message',
      sentAt: AppClock.now(),
      status: MessageStatus.none,
    );
    await _messageDao.upsert(_mapper.toEntity(model: message));
    await _touchChatRow(chatId, message, incrementUnread: true);
    await _syncRepository.advanceCursor(message.seq);
  }

  /// Updates the parent chat row after a message is persisted: last-message preview +
  /// timestamp (→ newest-first reorder), and optionally the unread count. Works at the
  /// [ChatEntity] level via a record-key lookup ([ChatDao.getById]) — no mapper needed.
  /// No-op if the chat row is absent.
  Future<void> _touchChatRow(String chatId, MessageModel message, {required bool incrementUnread}) async {
    final chat = await _chatDao.getById(chatId);
    if (chat == null) return;
    await _chatDao.upsert(
      chat.copyWith(
        lastMessagePreview: chatPreviewFor(message),
        lastMessageAt: message.sentAt.toUtc().toIso8601String(),
        unreadCount: incrementUnread ? chat.unreadCount + 1 : chat.unreadCount,
      ),
    );
  }

  @override
  Future<void> clean() async {
    await _messageDao.cleanData();
  }
}
