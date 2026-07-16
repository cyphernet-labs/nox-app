import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/data/local/chat/message_dao.dart';
import 'package:nox_app/data/mapper/chat/message_mapper.dart';
import 'package:nox_app/data/remote/api/chat/get_messages_api.dart';
import 'package:nox_app/data/remote/api/chat/send_message_api.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';

/// Cache-first chat thread (5.2) over the local Sembast DB. The deterministic mock
/// ([GetMessagesApi]) seeds a chat's history ONCE on first open; thereafter the
/// thread is paginated FROM the DB (newest batch first), and [sendMessage] persists
/// the accepted message locally. No backend — when transport lands, only the
/// seed/source swaps; the DB contract stays.
@LazySingleton(as: MessageRepository, env: [Environment.dev, Environment.prod, Environment.test])
class MessageRepositoryImpl with BaseRepositoryHelper implements MessageRepository {
  MessageRepositoryImpl(this._messageDao, this._getMessagesApi, this._sendMessageApi, this._mapper);

  final MessageDao _messageDao;
  final GetMessagesApi _getMessagesApi;
  final SendMessageApi _sendMessageApi;
  final MessageMapper _mapper;

  static const int _pageSize = GetMessagesConfig.pageSize;

  /// One-time seed of a chat's deterministic mock history into the DB (empty chat).
  Future<void> _seedChatIfEmpty(String chatId) async {
    if (await _messageDao.countByChat(chatId) > 0) return;
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
    await _messageDao.saveData(all.map((m) => _mapper.toEntity(model: m)).toList());
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
  Future<RepositoryResult<MessageModel>> sendMessage({required String chatId, String? text, MessageAttachment? attachment}) {
    return execute<MessageModel>(() async {
      final message = await _sendMessageApi.execute(chatId: chatId, text: text, attachment: attachment);
      await _messageDao.upsert(_mapper.toEntity(model: message));
      return RepositoryResult<MessageModel>.success(data: message);
    });
  }

  @override
  Future<void> clean() async {
    await _messageDao.cleanData();
  }
}
