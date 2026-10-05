import 'package:freezed_annotation/freezed_annotation.dart';

part 'unfinished_upload.freezed.dart';

/// An upload the server holds part of (contract §7, phase 043): what a later
/// attempt needs to go on from where the last one stopped instead of from the
/// first byte - after a broken link, a change of path or a restart of the app.
///
/// The source's size and modification time are a fingerprint, not decoration.
/// Every byte sent under [fileId] is taken as the same file's, so a source that
/// changed since would put the start of one file and the end of another under
/// one id. A changed source is not continued at all.
@freezed
abstract class UnfinishedUpload with _$UnfinishedUpload {
  const factory UnfinishedUpload({
    /// The server's id for the upload that has not finished.
    required String fileId,

    /// The source's size when the server named the upload.
    required int sourceSize,

    /// The source's modification time then.
    required DateTime sourceModifiedAt,
  }) = _UnfinishedUpload;
}
