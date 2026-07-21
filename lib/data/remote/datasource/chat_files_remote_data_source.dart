import 'package:nox_app/domain/model/chat/message_attachment.dart';

/// Network boundary for a chat's shared files (5.4). Kept distinct from
/// [ChatRemoteDataSource] per the data-layer inventory (feature 016).
abstract class ChatFilesRemoteDataSource {
  Future<List<MessageAttachment>> getChatFiles({required String chatId});
}
