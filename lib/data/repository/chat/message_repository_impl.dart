import 'package:injectable/injectable.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/data/remote/api/chat/get_messages_api.dart';
import 'package:nox_app/data/remote/api/chat/send_message_api.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';

/// Network-only chat thread (no DAO/subject — the carve-out, second after the chats
/// list). UI-phase source is mock ([GetMessagesApi] / [SendMessageApi]). Wraps every
/// call in `BaseRepositoryHelper.execute` (logs + maps errors). `// TODO(backend):`
/// real transport + cache-first watch when the backend lands.
@LazySingleton(as: MessageRepository, env: [Environment.dev, Environment.prod, Environment.test])
class MessageRepositoryImpl with BaseRepositoryHelper implements MessageRepository {
  MessageRepositoryImpl(this._getMessagesApi, this._sendMessageApi);

  final GetMessagesApi _getMessagesApi;
  final SendMessageApi _sendMessageApi;

  @override
  Future<RepositoryResult<(List<MessageModel>, PageMetadata)>> getMessages({required GetMessagesConfig config}) {
    return execute<(List<MessageModel>, PageMetadata)>(() async {
      final (messages, metadata) = await _getMessagesApi.execute(config: config);
      return RepositoryResult<(List<MessageModel>, PageMetadata)>.success(data: (messages, metadata));
    });
  }

  @override
  Future<RepositoryResult<MessageModel>> sendMessage({required String chatId, String? text, MessageAttachment? attachment}) {
    return execute<MessageModel>(() async {
      final message = await _sendMessageApi.execute(chatId: chatId, text: text, attachment: attachment);
      return RepositoryResult<MessageModel>.success(data: message);
    });
  }

  @override
  Future<void> clean() async {}
}
