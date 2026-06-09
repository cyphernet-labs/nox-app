import 'package:freezed_annotation/freezed_annotation.dart';

part 'page_metadata.freezed.dart';

/// Offset-style page metadata (default flavor). nextPage == null => last page.
/// JSON parsing lives in the data layer; this is the domain-side shape the
/// repository returns alongside a page slice.
@freezed
abstract class PageMetadata with _$PageMetadata {
  const factory PageMetadata({
    /// Total item count across all pages.
    required int total,

    /// 1-based index of the next page, or null on the last page.
    int? nextPage,
  }) = _PageMetadata;
}
