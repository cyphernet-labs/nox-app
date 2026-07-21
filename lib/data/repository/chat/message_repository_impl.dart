import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/data/local/chat/chat_dao.dart';
import 'package:nox_app/data/local/chat/message_dao.dart';
import 'package:nox_app/data/mapper/chat/message_mapper.dart';
import 'package:nox_app/data/remote/api/chat/get_messages_api.dart';
import 'package:nox_app/data/remote/api/chat/send_message_api.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:nox_app/general/formatters/chat_preview_formatter.dart';
import 'package:nox_app/general/identity/identity_resolver.dart';
import 'package:nox_app/general/identity_mock_data.dart';
import 'package:uuid/uuid.dart';

/// Cache-first chat thread (5.2) over the local Sembast DB. The deterministic mock
/// ([GetMessagesApi]) seeds a chat's history ONCE on first open; thereafter the
/// thread is paginated FROM the DB (newest batch first), and [sendMessage] persists
/// the accepted message locally. No backend — when transport lands, only the
/// seed/source swaps; the DB contract stays.
@LazySingleton(as: MessageRepository, env: [Environment.dev, Environment.prod, Environment.test])
class MessageRepositoryImpl with BaseRepositoryHelper implements MessageRepository {
  MessageRepositoryImpl(this._messageDao, this._getMessagesApi, this._sendMessageApi, this._mapper, this._chatDao, this._sessionRepository);

  final MessageDao _messageDao;
  final GetMessagesApi _getMessagesApi;
  final SendMessageApi _sendMessageApi;
  final MessageMapper _mapper;
  final ChatDao _chatDao;
  final SessionRepository _sessionRepository;

  static const int _pageSize = GetMessagesConfig.pageSize;
  static const Uuid _uuid = Uuid();

  /// The signed-in own-identity resolved from the session (fallbacks when absent).
  Future<Identity> _identity() async => resolveIdentity((await _sessionRepository.readSession()).data);

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
    var page = GetMessagesConfig.defaultPage;
    while (true) {
      final (messages, meta) = await _getMessagesApi.execute(
        config: GetMessagesConfig.nextPage(chatId: chatId, page: page),
      );
      all.addAll(messages);
      final next = meta.nextPage;
      if (next == null) break;
      page = next;
    }
    final reconciled = all.map((m) {
      if (m.authorId != IdentityMockData.fallbackOwnId) return m;
      return m.copyWith(authorId: identity.id, authorLabel: identity.label);
    });
    await _messageDao.saveData(reconciled.map((m) => _mapper.toEntity(model: m)).toList());
  }

  @override
  Future<RepositoryResult<(List<MessageModel>, PageMetadata)>> getMessages({required GetMessagesConfig config}) {
    return execute<(List<MessageModel>, PageMetadata)>(() async {
      await _seedChatIfEmpty(config.chatId);
      final all = (await _messageDao.getByChatSorted(config.chatId)).map((e) => _mapper.toModel(entity: e)).toList();
      final total = all.length;
      // page 1 = newest `pageSize`; each next page reaches further back in time.
      final end = total - (config.page - 1) * _pageSize;
      if (end <= 0) {
        return RepositoryResult<(List<MessageModel>, PageMetadata)>.success(data: (const <MessageModel>[], PageMetadata(total: total)));
      }
      final start = (end - _pageSize) < 0 ? 0 : end - _pageSize;
      final slice = all.sublist(start, end);
      final hasMore = start > 0;
      return RepositoryResult<(List<MessageModel>, PageMetadata)>.success(
        data: (slice, PageMetadata(total: total, nextPage: hasMore ? config.page + 1 : null)),
      );
    });
  }

  @override
  Stream<List<MessageModel>> watchMessages(String chatId) async* {
    await _seedChatIfEmpty(chatId);
    yield* _messageDao.watch(chatId).map((entities) => entities.map((e) => _mapper.toModel(entity: e)).toList());
  }

  @override
  Future<RepositoryResult<MessageModel>> sendMessage({required String chatId, String? text, MessageAttachment? attachment}) {
    return execute<MessageModel>(() async {
      final identity = await _identity();
      final message = await _sendMessageApi.execute(
        chatId: chatId,
        authorId: identity.id,
        authorLabel: identity.label,
        text: text,
        attachment: attachment,
      );
      await _messageDao.upsert(_mapper.toEntity(model: message));
      // Keep the chat row (list) consistent with the thread: update preview + time + order.
      // A failed send returns an error before reaching here, so the row is never touched (FR-004).
      await _touchChatRow(chatId, message, incrementUnread: false);
      return RepositoryResult<MessageModel>.success(data: message);
    });
  }

  @override
  Future<void> simulateIncoming({required String chatId}) async {
    // Debug stand-in for a server push: an inbound message (author != me) + unread bump.
    final message = MessageModel(
      id: 'sim_${_uuid.v4()}',
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
