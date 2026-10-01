import 'package:freezed_annotation/freezed_annotation.dart';

part 'attachment_transfer.freezed.dart';

/// Which way an attachment's bytes are going.
enum TransferDirection {
  /// From this device to the server: a message with a file being sent.
  upload,

  /// From the server to this device: a received picture being fetched.
  download,
}

/// An attachment whose bytes are moving right now, as the thread draws it.
///
/// In memory only. A transfer is a fact about this process: after a restart
/// the queue sends the file again from its first byte, and a percentage kept
/// from before would claim progress nobody has.
@freezed
abstract class AttachmentTransfer with _$AttachmentTransfer {
  const AttachmentTransfer._();

  const factory AttachmentTransfer({
    required TransferDirection direction,

    /// How much has moved, 0 to 1; null until the first bytes do. Before
    /// that the server is still being asked for a pass, which takes a while
    /// through Tor, and a ring standing at zero would read as a stall.
    double? fraction,
  }) = _AttachmentTransfer;

  /// Whole percent moved, for the caption; null while [fraction] is.
  int? get percent {
    final value = fraction;
    return value == null ? null : (value.clamp(0.0, 1.0) * 100).floor();
  }
}
