import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';

/// Network boundary for the chats list (5.1). The repository depends on this
/// interface, not a concrete source, so swapping the mock for a real HTTP
/// implementation is a DI binding change (feature 016). The mock implementation
/// lives in `datasource/mock/`; a future real one registers for `Environment.prod`.
abstract class ChatRemoteDataSource {
  Future<(List<ChatModel>, PageMetadata)> getChats({required GetChatsConfig config});
}
