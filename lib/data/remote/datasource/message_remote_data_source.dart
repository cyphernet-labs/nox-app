import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/chat/wire/messages_wire_entity.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';

/// Network boundary for a chat thread (5.2), aggregating the feature's two
/// operations — read history + send — behind one interface (feature 016). The
/// repository depends on this, not on the concrete mock generators. `getMessages`
/// carries the reference `ResponseEntity<MessagesWireEntity>` envelope (feature 018/S4);
/// `sendMessage` stays a single echo POST (envelope out of scope for S4).
abstract class MessageRemoteDataSource {
  Future<ResponseEntity<MessagesWireEntity>> getMessages({required GetMessagesConfig config});

  Future<MessageModel> sendMessage({
    required String chatId,
    required String authorId,
    required String authorLabel,
    String? text,
    MessageAttachment? attachment,
  });
}
