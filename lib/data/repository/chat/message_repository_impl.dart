import 'dart:async';
import 'dart:math';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/data/remote/socket/socket_channel_factory.dart';
import 'package:nox_app/data/local/chat/chat_dao.dart';
import 'package:nox_app/data/local/chat/message_dao.dart';
import 'package:nox_app/data/mapper/chat/message_mapper.dart';
import 'package:nox_app/data/mapper/chat/message_wire_mapper.dart';
import 'package:nox_app/data/remote/datasource/message_remote_data_source.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/data/entity/chat/message_entity.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
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
  MessageRepositoryImpl(this._messageDao, this._messageRemote, this._mapper, this._wireMapper, this._chatDao, this._sessionRepository);

  final MessageDao _messageDao;
  final MessageRemoteDataSource _messageRemote;
  final MessageMapper _mapper;
  final MessageWireMapper _wireMapper;
  final ChatDao _chatDao;
  final SessionRepository _sessionRepository;

  static const Uuid _uuid = Uuid();

  /// Fetches ONE batch from the source and merges it into the cache.
  ///
  /// Not a seed: the previous design walked a chat's entire history on first
  /// open, which is fine for a dozen mock rows and an unbounded download
  /// against a real chat (FR-016). Each call brings exactly the window the
  /// caller asked for.
  ///
  /// Merging matters as much as fetching: the wire carries no local delivery
  /// status and no device file path, so a row already stored keeps both.
  /// Returns the source's `has_more` for this window, or null when nothing was
  /// fetched. The cache cannot answer that question — it only knows what it
  /// holds — so discarding it would stop scroll-up at the edge of the cache and
  /// strand the rest of the history.
  Future<bool?> _fetchWindow(GetMessagesConfig config) async {
    final sessionResult = await _sessionRepository.readSession();
    // A failed session read must not bake own rows under the fallback identity
    // while a real session exists — they would render as a stranger's forever.
    if (!sessionResult.hasData) return null;
    final identity = resolveIdentity(sessionResult.data);
    final response = await _messageRemote.getMessages(config: config);
    final page = unwrapEnvelope(response, 'messages');
    final batch = _wireMapper.toListModel(entities: page.messages);
    if (batch.isEmpty) return page.hasMore;

    final rows = <MessageEntity>[];
    for (final wire in batch) {
      final existing = await _messageDao.getById(wire.id);
      var model = wire;
      // The mock source stamps own rows with a fixed fallback id; follow the
      // signed-in identity so own-detection matches the session (feature 015).
      if (model.authorId == IdentityMockData.fallbackOwnId) {
        model = model.copyWith(authorId: identity.id, authorLabel: identity.label);
      }
      if (model.authorId == identity.id) model = model.copyWith(status: MessageStatus.sent);
      if (existing != null) {
        model = model.copyWith(
          attachment: model.attachment?.copyWith(localPath: existing.attachmentLocalPath),
          status: _mapper.toModel(entity: existing).status,
        );
      }
      rows.add(_mapper.toEntity(model: model));
    }
    await _messageDao.saveData(rows);
    await _ensureGenesis(config.chatId, batch);
    return page.hasMore;
    // The cursor is deliberately NOT advanced here. It promises "every event up
    // to this seq is applied", and fetching one chat's window says nothing about
    // another chat's events with lower numbers — advancing past them would make
    // the next catch-up skip them, losing messages silently. Only an applied
    // event (SyncService) and the first greeting may move it.
  }

  /// The opening "chat created by X" line is client-side: the contract has no
  /// system messages on the wire (§4). Authored from the CHAT's own creator so
  /// a real chat names its real creator rather than a mock persona, and given
  /// the seq below the batch so it stays at the top of the thread.
  Future<void> _ensureGenesis(String chatId, List<MessageModel> batch) async {
    final id = '${chatId}_sys';
    final lowest = batch.map((m) => m.seq).reduce(min);
    final existing = await _messageDao.getById(id);
    if (existing != null) {
      // Already below everything loaded — leave it where it is.
      if ((existing.seq ?? 0) < lowest) return;
      // Scrolling up brought history older than the window this line was first
      // anchored against. Without re-anchoring it would sit in the MIDDLE of
      // the thread, and could even collide with a real message's seq.
      await _messageDao.upsert(existing.copyWith(seq: lowest - 1));
      return;
    }
    final chat = await _chatDao.getById(chatId);
    final label = (chat?.createdByLabel?.isNotEmpty ?? false) ? chat!.createdByLabel! : ChatSeedMockData.genesisAuthorLabel;
    await _messageDao.upsert(
      _mapper.toEntity(
        model: MessageModel(
          id: id,
          seq: lowest - 1,
          chatId: chatId,
          authorId: 'system',
          authorLabel: label,
          isSystem: true,
          sentAt: AppClock.now().subtract(ChatSeedMockData.genesisAge),
        ),
      ),
    );
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
      await _backfillLegacySeqIfNeeded(config.chatId);
      bool? sourceHasMore;
      try {
        // A cache-only read never reaches the wire (the live refresh tick).
        if (!config.cachedOnly) sourceHasMore = await _fetchWindow(config);
      } on SocketUnavailableException {
        // A dead channel falls back to what is cached; a typed refusal is an
        // answer and must reach the caller.
        logRepository.debug(target: this, message: 'thread: serving from cache (channel down)');
      }
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
      // There is more to load if EITHER side says so. The source knows about
      // history this device never fetched; the cache knows about rows outside
      // this window (a locally sent message, an older window pulled earlier).
      // Trusting one alone either stops scroll-up at the edge of the cache or
      // claims the thread is exhausted while it is not.
      return RepositoryResult<(List<MessageModel>, PageMetadata)>.success(
        data: (slice, PageMetadata(hasMore: (sourceHasMore ?? false) || start > 0)),
      );
    });
  }

  @override
  Stream<List<MessageModel>> watchMessages(String chatId) async* {
    // A pure projection: fetching belongs to the paged read, which is the only
    // caller that knows WHICH window is wanted.
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
      // Below every server seq (which start at 1): the opening line belongs at
      // the top of the thread, and MockSeq's clock-derived value would pin it
      // to the bottom of a live chat forever.
      seq: 0,
      chatId: chatId,
      authorId: 'system',
      authorLabel: identity.label, // renders "Chat created by {label}" via l10n.systemChatCreated
      sentAt: AppClock.now(),
      isSystem: true,
    );
    await _messageDao.upsert(_mapper.toEntity(model: systemLine));
  }

  @override
  Future<List<MessageAttachment>> chatFiles({required String chatId, bool refresh = false}) async {
    // Derive the 5.4 shared-files view from the chat's persisted attachments,
    // newest-first (feature 017). Pull the newest window first so the view is
    // useful even when the files panel is opened before the thread; a dead
    // channel just shows what is cached.
    if (refresh) {
      try {
        await _fetchWindow(GetMessagesConfig.tail(chatId: chatId));
      } on SocketUnavailableException {
        // The cached view is the right answer while the channel is down.
      }
    }
    final messages = (await _messageDao.getByChatSorted(chatId)).map((e) => _mapper.toModel(entity: e)).toList();
    final files = <MessageAttachment>[];
    for (final message in messages.reversed) {
      final attachment = message.attachment;
      if (attachment != null) files.add(attachment);
    }
    return files;
  }

  @override
  Future<void> attachLocalFile({required String messageId, required String localPath}) async {
    final stored = await _messageDao.getById(messageId);
    // Gone, or never had an attachment: nothing to point anywhere.
    if (stored == null || stored.attachmentId == null) return;
    await _messageDao.upsert(stored.copyWith(attachmentLocalPath: localPath));
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
