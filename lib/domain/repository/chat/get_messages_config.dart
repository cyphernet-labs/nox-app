import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/repository/base/repository_config.dart';

part 'get_messages_config.freezed.dart';

/// Cursor request for one backward batch of a chat's history (contract v0 §5
/// `messages.list`): [beforeSeq] absent → the newest tail; otherwise the
/// [limit] newest messages strictly older than [beforeSeq]. Batches ascend by
/// seq internally; there are no page numbers and no totals for messages.
@freezed
abstract class GetMessagesConfig with _$GetMessagesConfig implements RepositoryConfig {
  const factory GetMessagesConfig({
    required String chatId,

    /// Exclusive upper bound: return messages with `seq < beforeSeq`.
    /// Null = from the newest end.
    int? beforeSeq,

    /// Batch size; the server caps it at 100 (contract §5).
    @Default(GetMessagesConfig.pageSize) int limit,
  }) = _GetMessagesConfig;

  static const int pageSize = 20;

  /// The newest tail of the thread (initial load and refresh).
  static GetMessagesConfig tail({required String chatId, int limit = pageSize}) => GetMessagesConfig(chatId: chatId, limit: limit);

  /// The batch preceding the oldest loaded message (scroll-up prefetch).
  static GetMessagesConfig olderThan({required String chatId, required int beforeSeq, int limit = pageSize}) =>
      GetMessagesConfig(chatId: chatId, beforeSeq: beforeSeq, limit: limit);
}
