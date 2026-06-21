import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/repository/base/repository_config.dart';

part 'get_chats_config.freezed.dart';

/// Per-call config for the chats list (5.1). Mirrors `GetItemsConfig`: a 1-based
/// `page` + an optional `search` query (server-side filter; the UI-phase mock
/// filters by chat name). `// TODO(backend):` real server search semantics.
@freezed
abstract class GetChatsConfig with _$GetChatsConfig implements RepositoryConfig {
  const GetChatsConfig._();

  const factory GetChatsConfig({required int page, String? search}) = _GetChatsConfig;

  factory GetChatsConfig.firstPage({String? search}) => GetChatsConfig(page: defaultPage, search: search);

  factory GetChatsConfig.nextPage({required int page, String? search}) => GetChatsConfig(page: page, search: search);

  static const int pageSize = 20;
  static const int defaultPage = 1;
}
