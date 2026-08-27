import 'package:freezed_annotation/freezed_annotation.dart';

part 'page_metadata.freezed.dart';

/// Contract-shaped page metadata: the server reports only whether more rows
/// exist beyond this slice (no totals on the wire). nextPage carries the
/// 1-based next page index for the paged chats path; the cursor-paged
/// messages path leaves it null and advances by before_seq instead.
@freezed
abstract class PageMetadata with _$PageMetadata {
  const factory PageMetadata({
    /// Whether rows exist beyond this slice (wire has_more).
    required bool hasMore,

    /// 1-based index of the next page (paged path only), null otherwise.
    int? nextPage,
  }) = _PageMetadata;
}
