import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/repository/base/repository_config.dart';

part 'get_messages_config.freezed.dart';

/// Cursor request for one backward batch of a chat's history (contract v0 §5
/// `messages.list`): [beforeSeq] absent → the newest tail; otherwise the
/// [limit] newest messages strictly older than [beforeSeq]. Batches ascend by
/// seq internally; there are no page numbers and no totals for messages.
@freezed
abstract class GetMessagesConfig with _$GetMessagesConfig implements RepositoryConfig {
  const GetMessagesConfig._();

  const factory GetMessagesConfig({
    required String chatId,

    /// Exclusive upper bound: return messages with `seq < beforeSeq`.
    /// Null = from the newest end.
    int? beforeSeq,

    /// Batch size. Always within [maxLimit] — the factories clamp it.
    @Default(GetMessagesConfig.pageSize) int limit,

    /// Serve this window from the local cache without touching the server.
    ///
    /// The live change-signal fires on every persisted row, so a refresh that
    /// fetched would persist, wake the signal and fetch again — a loop that
    /// never settles. Events already keep the cache current; the tick only
    /// needs to re-project it.
    @Default(false) bool cachedOnly,
  }) = _GetMessagesConfig;

  static const int pageSize = 20;

  /// The server's hard ceiling on one batch (contract §5). It clamps a larger
  /// request SILENTLY, so asking for more than this does not fail — it just
  /// returns fewer rows than the caller believes it asked for. Clamping here
  /// keeps that mismatch impossible instead of merely unlikely.
  static const int maxLimit = 100;

  /// The newest tail of the thread (initial load and refresh).
  static GetMessagesConfig tail({required String chatId, int limit = pageSize, bool cachedOnly = false}) =>
      GetMessagesConfig(chatId: chatId, limit: limit, cachedOnly: cachedOnly);

  /// The batch preceding the oldest loaded message (scroll-up prefetch).
  static GetMessagesConfig olderThan({required String chatId, required int beforeSeq, int limit = pageSize}) =>
      GetMessagesConfig(chatId: chatId, beforeSeq: beforeSeq, limit: limit);

  static int _clamp(int limit) => limit > maxLimit ? maxLimit : limit;

  /// Whether this config is asking for more than one wire batch can carry.

  /// The value safe to put on the wire. The ceiling is the SERVER's, so it is
  /// applied here rather than in the factories: a cache-only read is served
  /// locally and may legitimately ask for a wider window — clamping it there
  /// would leave rows the cache holds unreachable.
  int get wireLimit => _clamp(limit);
}
