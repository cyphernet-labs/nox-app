import 'package:nox_app/domain/model/file/transfer_cancellation.dart';
import 'package:nox_app/domain/model/file/unfinished_upload.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

/// How far a transfer has got, as a fraction of the whole.
typedef TransferFraction = void Function(double fraction);

/// The file chain (contract v0 §7): bytes to the server and back.
///
/// Takes and returns PATHS, never `dart:io` types — `domain` imports nothing,
/// and a file handle would drag a platform library in for a value that is a
/// string anyway. The picker seam already made the same choice.
abstract class FileRepository {
  /// Declares the file, sends its bytes, and returns the server's id for it —
  /// but ONLY once the bytes are confirmed there.
  ///
  /// Returning the id any earlier would let a message point at a file that has
  /// none: the server accepts such a message, and the recipient can never
  /// download it.
  ///
  /// Continues [from] when given, sending only what the server does not have
  /// yet (phase 043). [onUnfinished] hears every change to what is worth
  /// continuing - the upload the server has just named, or null once there is
  /// nothing to continue - and the first byte waits until it has been heard: a
  /// restart in the middle has to find the upload written down. A source that
  /// vanished, changed or cannot be read is `notFound`, and is never
  /// continued. A change of path under the transfer is not a failure: the rest
  /// goes at once by the new one, within the same call. [cancellation] ends the
  /// transfer as a broken connection would - its message was thrown away.
  Future<RepositoryResult<String>> upload({
    required String path,
    required String mime,
    UnfinishedUpload? from,
    Future<void> Function(UnfinishedUpload? upload)? onUnfinished,
    TransferFraction? onProgress,
    TransferCancellation? cancellation,
  });

  /// Brings the bytes to this device and returns where they landed.
  ///
  /// ONE attempt, going on from whatever an earlier one left on this device
  /// (phase 043) - after a break and after a restart alike; a change of path
  /// under it is not the end of the attempt, which goes on at once by the new
  /// one. Bytes of another
  /// version of the file are thrown away, and a file is complete only when it
  /// is as long as [expectedSize] says. A second caller for the same file
  /// joins the attempt under way and hears its progress from where it stands.
  Future<RepositoryResult<String>> download({
    required String fileId,
    required String suggestedName,
    int? expectedSize,
    TransferFraction? onProgress,
  });

  /// Whether the bytes for [fileId] are already on this device.
  Future<String?> localPathFor({required String fileId, required String suggestedName});

  /// Ends every transfer under way, both ways (logout, change of server). Each
  /// ends as a broken connection would, and each could be continued - but a
  /// download begun before this call writes nothing to this device after it.
  Future<void> cancelTransfers();

  /// Drops every downloaded byte, finished or not (logout). They are other
  /// people's pictures.
  Future<void> clean();
}
