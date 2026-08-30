import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/chat/wire/message_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/messages_wire_entity.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';

/// Network boundary for a chat thread (5.2), aggregating the feature's two
/// operations — read history + send — behind one interface (feature 016). The
/// repository depends on this, not on the concrete mock generators. BOTH operations
/// carry the `ResponseEntity<...>` envelope (feature 018, wire shapes aligned to
/// contract v0 in 025): a page `{messages, has_more}` for the cursor read, and the
/// accepted message for the send echo.
abstract class MessageRemoteDataSource {
  Future<ResponseEntity<MessagesWireEntity>> getMessages({required GetMessagesConfig config});

  /// Sends one message.
  ///
  /// The author is NOT passed: the server knows who sent the command
  /// (contract §5). [clientMessageId] is the idempotency key — the caller owns
  /// it and must reuse it on every retry of the same message, which is what
  /// makes a resend after a lost reply safe.
  ///
  /// [attachment] stays in the signature for the mock path. On the live path
  /// there is no `file_id` until the file chain lands (phase 028), so a send
  /// carrying one is refused before it reaches the wire rather than silently
  /// dropping the file.
  Future<ResponseEntity<MessageWireEntity>> sendMessage({
    required String chatId,
    required String clientMessageId,
    String? text,
    MessageAttachment? attachment,
  });
}
