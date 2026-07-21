import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';

/// Network boundary for a chat thread (5.2), aggregating the feature's two
/// operations — read history + send — behind one interface (feature 016). The
/// repository depends on this, not on the concrete mock generators.
abstract class MessageRemoteDataSource {
  Future<(List<MessageModel>, PageMetadata)> getMessages({required GetMessagesConfig config});

  Future<MessageModel> sendMessage({
    required String chatId,
    required String authorId,
    required String authorLabel,
    String? text,
    MessageAttachment? attachment,
  });
}
