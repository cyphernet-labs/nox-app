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
  }) = _GetMessagesConfig;

  static const int pageSize = 20;

  /// The server's hard ceiling on one batch (contract §5). It clamps a larger
  /// request SILENTLY, so asking for more than this does not fail — it just
  /// returns fewer rows than the caller believes it asked for. Clamping here
  /// keeps that mismatch impossible instead of merely unlikely.
  static const int maxLimit = 100;

  /// The newest tail of the thread (initial load and refresh).
  static GetMessagesConfig tail({required String chatId, int limit = pageSize}) => GetMessagesConfig(chatId: chatId, limit: _clamp(limit));

  /// The batch preceding the oldest loaded message (scroll-up prefetch).
  static GetMessagesConfig olderThan({required String chatId, required int beforeSeq, int limit = pageSize}) =>
      GetMessagesConfig(chatId: chatId, beforeSeq: beforeSeq, limit: _clamp(limit));

  static int _clamp(int limit) => limit > maxLimit ? maxLimit : limit;

  /// The value actually safe to put on the wire. Built directly rather than
  /// through the factories, a config can still carry an over-large [limit] —
  /// the server would clamp it silently, so the data source reads this instead.
  int get wireLimit => _clamp(limit);
}
