import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/data/exception/file_transfer_exception.dart';
import 'package:nox_app/data/remote/datasource/file_remote_data_source.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';
import 'package:path_provider/path_provider.dart';

/// The file chain over the data source (contract v0 §7).
///
/// Downloaded bytes live in a CACHE directory named by file id. Not the
/// database — Sembast is a document store and blobs do not belong in it. Not
/// the documents directory — this is cache: losing it costs one re-download,
/// while documents are backed up and synced, which is the wrong promise for
/// somebody else's picture.
@LazySingleton(as: FileRepository, env: [Environment.dev, Environment.prod, Environment.test])
class FileRepositoryImpl with BaseRepositoryHelper implements FileRepository {
  FileRepositoryImpl(this._remote, this._config);

  final FileRemoteDataSource _remote;
  final AppConfigRepository _config;

  static const String _cacheFolder = 'nox_attachments';

  @override
  Future<RepositoryResult<String>> upload({required String path, required String mime, TransferFraction? onProgress}) {
    return execute<String>(() async {
      final file = File(path);
      // The file was picked minutes or hours ago and the queue only reaches it
      // now; it may be gone or changed since.
      if (!file.existsSync()) throw RepositoryException.notFound;
      final size = await file.length();

      // Checked here as a backstop. The composer checks first, where the person
      // is still looking at the screen — this catches a file that grew, or a
      // build that skipped the composer path.
      if (size > _config.limits.maxAttachmentBytes) throw RepositoryException.payloadTooLarge;

      // A pass is one-shot and lives ten minutes, so it can be dead before the
      // first byte moves — the contract calls that routine and says to ask for
      // another. Handling it here means the queue never sees a refusal it would
      // have to interpret, and it cannot loop: exactly one second chance.
      final fileId =
          await _uploadOnce(file, path, mime, size, onProgress) ?? await _uploadOnce(file, path, mime, size, onProgress, lastChance: true);
      return RepositoryResult<String>.success(data: fileId!);
    });
  }

  /// One full declare-and-send. Returns null when the pass was refused and it
  /// is worth asking for another; throws for anything else.
  Future<String?> _uploadOnce(
    File file,
    String path,
    String mime,
    int size,
    TransferFraction? onProgress, {
    bool lastChance = false,
  }) async {
    final ticket = unwrapEnvelope(await _remote.uploadBegin(name: _nameOf(path), sizeBytes: size, mime: mime), 'uploadBegin');
    try {
      await _remote.putBytes(
        uploadPath: ticket.uploadUrl,
        file: file,
        onProgress: onProgress == null ? null : (done, total) => onProgress(total == 0 ? 0 : done / total),
      );
    } on FileTransferException catch (e) {
      switch (e.failure) {
        case FileTransferFailure.passRejected:
          // Out of second chances: report it as a connection-class failure so
          // the queue waits and tries the whole thing again later, rather than
          // giving up on the message.
          if (lastChance) throw RepositoryException.connection;
          return null;
        case FileTransferFailure.sizeMismatch:
          // What is on disk is not what was announced — announcing it again
          // fails identically, so this message is done.
          throw RepositoryException.invalidRequest;
        case FileTransferFailure.connection:
          throw RepositoryException.connection;
      }
    }
    // Only now is the id true: the bytes are on the server.
    return ticket.fileId;
  }

  @override
  Future<RepositoryResult<String>> download({required String fileId, required String suggestedName, TransferFraction? onProgress}) {
    return execute<String>(() async {
      final destination = File(await _cachePathFor(fileId, suggestedName));
      if (destination.existsSync()) return RepositoryResult<String>.success(data: destination.path);
      await destination.parent.create(recursive: true);

      // Download to a SIDE file and rename on success. Dio writes straight to
      // the path it is given, with no atomic finish, so a transfer cut short by
      // a lost link or a killed process would leave a half file sitting exactly
      // where a complete one belongs — and every later reader, this method
      // included, treats existence as proof of completeness. The picture would
      // render as garbage forever, and nothing would ever try again.
      final partial = File('${destination.path}.part');
      if (partial.existsSync()) await partial.delete();

      final ticket = unwrapEnvelope(await _remote.downloadBegin(fileId: fileId), 'downloadBegin');
      try {
        await _remote.getBytes(
          downloadPath: ticket.downloadUrl,
          destination: partial,
          onProgress: onProgress == null ? null : (done, total) => onProgress(total <= 0 ? 0 : done / total),
        );
      } on FileTransferException catch (e) {
        if (partial.existsSync()) await partial.delete();
        throw e.failure == FileTransferFailure.sizeMismatch ? RepositoryException.invalidRequest : RepositoryException.connection;
      }
      // The rename is the moment the file becomes real. Before it, nothing that
      // looks like a cache hit exists.
      await partial.rename(destination.path);
      return RepositoryResult<String>.success(data: destination.path);
    });
  }

  @override
  Future<String?> localPathFor({required String fileId, required String suggestedName}) async {
    final path = await _cachePathFor(fileId, suggestedName);
    return File(path).existsSync() ? path : null;
  }

  @override
  Future<void> clean() async {
    final dir = Directory('${(await getApplicationCacheDirectory()).path}/$_cacheFolder');
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  /// Keyed by file id, so two files that share a display name cannot collide;
  /// the name is kept only for the extension, which is what decoders sniff.
  Future<String> _cachePathFor(String fileId, String suggestedName) async {
    final root = await getApplicationCacheDirectory();
    final ext = suggestedName.contains('.') ? suggestedName.split('.').last : '';
    return '${root.path}/$_cacheFolder/$fileId${ext.isEmpty ? '' : '.$ext'}';
  }

  String _nameOf(String path) => path.split(Platform.pathSeparator).last;
}
