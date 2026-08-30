import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/repository/base/repository_config.dart';

part 'get_chats_config.freezed.dart';

/// Per-call config for the chats list (5.1) — the PAGED path of contract v0 §4:
/// a 1-based `page` (+ `page_size`) plus an optional `search` query. The reply
/// carries `has_more`, never a total. Server-side search semantics are the
/// server's; the mock filters by chat name locally.
@freezed
abstract class GetChatsConfig with _$GetChatsConfig implements RepositoryConfig {
  const GetChatsConfig._();

  const factory GetChatsConfig({required int page, String? search}) = _GetChatsConfig;

  factory GetChatsConfig.firstPage({String? search}) => GetChatsConfig(page: defaultPage, search: search);

  factory GetChatsConfig.nextPage({required int page, String? search}) => GetChatsConfig(page: page, search: search);

  static const int pageSize = 20;
  static const int defaultPage = 1;
}
