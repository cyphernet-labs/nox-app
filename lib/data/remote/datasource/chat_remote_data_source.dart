import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/chat/wire/chats_wire_entity.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';

/// Network boundary for the chats list (5.1). The repository depends on this
/// interface, not a concrete source, so swapping the mock for a real HTTP
/// implementation is a DI binding change (feature 016). The boundary carries the
/// reference `ResponseEntity<ChatsWireEntity>` envelope (feature 018/S4 — uniform with
/// `ItemRemoteDataSource`); the repository unwraps it. The mock lives in `datasource/mock/`;
/// a future real one registers for `Environment.prod`.
abstract class ChatRemoteDataSource {
  Future<ResponseEntity<ChatsWireEntity>> getChats({required GetChatsConfig config});
}
