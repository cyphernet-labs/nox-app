import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/chat/wire/chats_wire_entity.dart';
import 'package:nox_app/data/remote/api/chat/get_chats_api.dart';
import 'package:nox_app/data/remote/datasource/chat_remote_data_source.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';

/// Mock [ChatRemoteDataSource] — delegates to the deterministic [GetChatsApi]
/// generator (which now returns the `ResponseEntity<ChatsWireEntity>` envelope, S4).
/// Bound for every environment the app boots (prod flavor boots `Environment.prod`;
/// no real impl exists yet). Flip to real: register a `RealChatRemoteDataSource` for
/// `[Environment.prod]` and scope this to `[dev, test]` — see
/// `specs/016-remote-datasource-seam/contracts/di-binding.md`.
@LazySingleton(as: ChatRemoteDataSource, env: [Environment.dev, Environment.prod, Environment.test])
class MockChatRemoteDataSource implements ChatRemoteDataSource {
  MockChatRemoteDataSource(this._api);

  final GetChatsApi _api;

  @override
  Future<ResponseEntity<ChatsWireEntity>> getChats({required GetChatsConfig config}) => _api.execute(config: config);
}
