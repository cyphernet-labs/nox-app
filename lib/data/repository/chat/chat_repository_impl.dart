import 'package:injectable/injectable.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/data/remote/api/chat/get_chats_api.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';

/// Network-only paginated chats list (no DAO/subject — the carve-out). UI-phase
/// source is a mock ([GetChatsApi]). Wraps every call in `BaseRepositoryHelper.execute`
/// (logs + maps errors to a RepositoryException). `// TODO(backend):` real transport
/// + cache-first watch when the backend lands.
@LazySingleton(as: ChatRepository, env: [Environment.dev, Environment.prod, Environment.test])
class ChatRepositoryImpl with BaseRepositoryHelper implements ChatRepository {
  ChatRepositoryImpl(this._getChatsApi);

  final GetChatsApi _getChatsApi;

  @override
  Future<RepositoryResult<(List<ChatModel>, PageMetadata)>> getChats({required GetChatsConfig config}) {
    return execute<(List<ChatModel>, PageMetadata)>(() async {
      final (chats, metadata) = await _getChatsApi.execute(config: config);
      return RepositoryResult<(List<ChatModel>, PageMetadata)>.success(data: (chats, metadata));
    });
  }

  @override
  Future<void> clean() async {}
}
