import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/chat/wire/message_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/messages_wire_entity.dart';
import 'package:nox_app/data/remote/api/chat/get_messages_api.dart';
import 'package:nox_app/data/remote/api/chat/send_message_api.dart';
import 'package:nox_app/data/remote/datasource/message_remote_data_source.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/general/identity/identity_resolver.dart';

/// Mock [MessageRemoteDataSource] — aggregates the two thread generators
/// ([GetMessagesApi] read + [SendMessageApi] send) behind one interface. Bound for
/// all boot environments; flip to real per `contracts/di-binding.md`.
@LazySingleton(as: MessageRemoteDataSource, env: [Environment.dev, Environment.prod, Environment.test])
class MockMessageRemoteDataSource implements MessageRemoteDataSource {
  MockMessageRemoteDataSource(this._getMessagesApi, this._sendMessageApi, this._sessionRepository);

  final GetMessagesApi _getMessagesApi;
  final SendMessageApi _sendMessageApi;
  final SessionRepository _sessionRepository;

  @override
  Future<ResponseEntity<MessagesWireEntity>> getMessages({required GetMessagesConfig config}) => _getMessagesApi.execute(config: config);

  @override
  Future<ResponseEntity<MessageWireEntity>> sendMessage({
    required String chatId,
    required String clientMessageId,
    String? text,
    MessageAttachment? attachment,
  }) async {
    // The mock stands in for the server, and the server is the side that knows
    // who sent a command — so it resolves the identity itself rather than being
    // told. Reading it from the session keeps own-message authorship (feature
    // 015) working exactly as before the author left the wire.
    final identity = resolveIdentity((await _sessionRepository.readSession()).data);
    return _sendMessageApi.execute(
      chatId: chatId,
      authorId: identity.id,
      authorLabel: identity.label,
      text: text,
      attachment: attachment,
    );
  }
}
