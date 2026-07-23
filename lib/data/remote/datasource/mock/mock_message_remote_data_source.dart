import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/chat/wire/messages_wire_entity.dart';
import 'package:nox_app/data/remote/api/chat/get_messages_api.dart';
import 'package:nox_app/data/remote/api/chat/send_message_api.dart';
import 'package:nox_app/data/remote/datasource/message_remote_data_source.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';

/// Mock [MessageRemoteDataSource] — aggregates the two thread generators
/// ([GetMessagesApi] read + [SendMessageApi] send) behind one interface. Bound for
/// all boot environments; flip to real per `contracts/di-binding.md`.
@LazySingleton(as: MessageRemoteDataSource, env: [Environment.dev, Environment.prod, Environment.test])
class MockMessageRemoteDataSource implements MessageRemoteDataSource {
  MockMessageRemoteDataSource(this._getMessagesApi, this._sendMessageApi);

  final GetMessagesApi _getMessagesApi;
  final SendMessageApi _sendMessageApi;

  @override
  Future<ResponseEntity<MessagesWireEntity>> getMessages({required GetMessagesConfig config}) => _getMessagesApi.execute(config: config);

  @override
  Future<MessageModel> sendMessage({
    required String chatId,
    required String authorId,
    required String authorLabel,
    String? text,
    MessageAttachment? attachment,
  }) => _sendMessageApi.execute(chatId: chatId, authorId: authorId, authorLabel: authorLabel, text: text, attachment: attachment);
}
