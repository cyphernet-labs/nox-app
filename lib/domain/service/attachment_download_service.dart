import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';

/// Brings attachment bytes to this device, and does not give up on a bad link
/// (phase 043).
///
/// A broken connection, a change of path or a stall only pause a download: it
/// goes on from the bytes already here once the pause - which grows, attempt by
/// attempt - is over, or at once when the channel comes back. Only a server that
/// keeps refusing ends it, or a refusal no retry can change.
///
/// The download belongs to the app, not to whoever asked: the file view (5.3)
/// can close and the bytes keep coming, and the path is recorded against the
/// message when they are all here - whether anyone is still listening or not.
abstract class AttachmentDownloadService {
  /// The bytes of [attachment] on this device: fetched, or joined when they are
  /// already on their way - a caller who joins hears at once how far they are.
  /// Resolves with the local path, or with what ended the download: a terminal
  /// refusal (`attachmentGone`, `notFound`), or a server that refused too many
  /// times in a row. The path is recorded against [messageId] when given.
  Future<RepositoryResult<String>> fetch({String? messageId, required MessageAttachment attachment, TransferFraction? onProgress});

  /// Stops telling [onProgress] how far a download has got - its screen closed.
  /// The download itself goes on.
  void stopListening(TransferFraction onProgress);

  /// Stops every download and waits until each has (logout, change of server):
  /// nothing may write into a cache that is about to be wiped. A fetch asked
  /// for while it runs is refused rather than started.
  Future<void> reset();
}
