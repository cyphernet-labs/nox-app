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

  const factory GetChatsConfig({
    required int page,
    String? search,

    /// Serve this page from the local cache without touching the server.
    ///
    /// The live change-signal re-reads the loaded window on every tick; doing
    /// that over the wire would fire one command per loaded page per event, at
    /// which point a busy chat would keep the app permanently fetching. Events
    /// already keep the cache current, so the tick only needs to re-project it.
    @Default(false) bool cachedOnly,
  }) = _GetChatsConfig;

  factory GetChatsConfig.firstPage({String? search}) => GetChatsConfig(page: defaultPage, search: search);

  factory GetChatsConfig.nextPage({required int page, String? search}) => GetChatsConfig(page: page, search: search);

  static const int pageSize = 20;
  static const int defaultPage = 1;
}
