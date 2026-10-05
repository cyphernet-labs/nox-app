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
  /// vanished or changed is `notFound`, and is never continued.
  Future<RepositoryResult<String>> upload({
    required String path,
    required String mime,
    UnfinishedUpload? from,
    Future<void> Function(UnfinishedUpload? upload)? onUnfinished,
    TransferFraction? onProgress,
  });

  /// Brings the bytes to this device and returns where they landed.
  Future<RepositoryResult<String>> download({required String fileId, required String suggestedName, TransferFraction? onProgress});

  /// Whether the bytes for [fileId] are already on this device.
  Future<String?> localPathFor({required String fileId, required String suggestedName});

  /// Drops every downloaded byte (logout). They are other people's pictures.
  Future<void> clean();
}
