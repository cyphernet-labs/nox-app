import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/base/error_wire_entity.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/chat/wire/message_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/messages_wire_entity.dart';
import 'package:nox_app/data/remote/datasource/message_remote_data_source.dart';
import 'package:nox_app/data/remote/datasource/real/socket_envelope.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';

/// The chat thread over the live socket (contract v0 §5).
@LazySingleton(as: MessageRemoteDataSource, env: [Environment.dev])
class RealMessageRemoteDataSource implements MessageRemoteDataSource {
  RealMessageRemoteDataSource(this._socket);

  final NoxSocketClient _socket;

  @override
  Future<ResponseEntity<MessagesWireEntity>> getMessages({required GetMessagesConfig config}) async {
    final reply = await _socket.send('messages.list', <String, dynamic>{
      'chat_id': config.chatId,
      'before_seq': ?config.beforeSeq,
      // wireLimit, not limit: a config built directly could carry a value above
      // the server's ceiling, which it would clamp silently.
      'limit': config.wireLimit,
    });
    return reply.toEnvelope(MessagesWireEntity.fromJson);
  }

  @override
  Future<ResponseEntity<MessageWireEntity>> sendMessage({
    required String chatId,
    required String clientMessageId,
    String? text,
    MessageAttachment? attachment,
  }) async {
    if (attachment != null) {
      // An attachment needs a file_id, which only the upload chain issues, and
      // that chain is phase 028. Refusing here is honest: sending text-only
      // would drop the file silently, and sending without either field would be
      // rejected by the server as a malformed command.
      return const ResponseEntity<MessageWireEntity>(
        success: false,
        error: ErrorWireEntity(code: 'invalid_request', message: 'attachments are not sent over the live channel yet'),
      );
    }
    final reply = await _socket.send('message.send', <String, dynamic>{
      'chat_id': chatId,
      'client_message_id': clientMessageId,
      'body': ?(text == null ? null : <String, dynamic>{'type': 'text', 'text': text}),
    });
    return reply.toWrappedEnvelope('message', MessageWireEntity.fromJson);
  }
}
