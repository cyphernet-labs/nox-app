import 'package:freezed_annotation/freezed_annotation.dart';

part 'upload_ticket.freezed.dart';

/// What the server hands back when a file is declared (contract v0 §7).
///
/// Deliberately NOT persisted. The pass is one-shot and lives ten minutes,
/// while a queued send can wait hours — by the time the drain reaches the
/// record it would be dead anyway, and a stored dead pass is worse than none:
/// it invites code to try it.
@freezed
abstract class UploadTicket with _$UploadTicket {
  const factory UploadTicket({
    /// The file's id on the server. This is what the message will reference,
    /// and it only becomes true once the bytes are actually there.
    required String fileId,

    /// RELATIVE path for the byte transfer — the server does not know its own
    /// public address (§7), so the base comes from the app's configured one.
    required String uploadPath,
    required int maxAttachmentBytes,
  }) = _UploadTicket;
}

/// The same, for getting bytes back.
@freezed
abstract class DownloadTicket with _$DownloadTicket {
  const factory DownloadTicket({required String downloadPath}) = _DownloadTicket;
}
