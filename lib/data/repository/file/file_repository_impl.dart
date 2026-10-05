import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/data/entity/file/upload_ticket_wire_entity.dart';
import 'package:nox_app/data/exception/file_transfer_exception.dart';
import 'package:nox_app/data/remote/datasource/file_remote_data_source.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/file/unfinished_upload.dart';
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
  Future<RepositoryResult<String>> upload({
    required String path,
    required String mime,
    UnfinishedUpload? from,
    Future<void> Function(UnfinishedUpload? upload)? onUnfinished,
    TransferFraction? onProgress,
  }) {
    return execute<String>(() async {
      final file = File(path);
      // The file was picked minutes or hours ago and the queue only reaches it
      // now; it may be gone or changed since.
      final source = await _sourceOf(file);

      // Checked here as a backstop. The composer checks first, where the person
      // is still looking at the screen — this catches a file that grew, or a
      // build that skipped the composer path.
      if (source.size > _config.limits.maxAttachmentBytes) throw RepositoryException.payloadTooLarge;

      // Bytes already on the server are this source's bytes only if the source
      // is the one they came from. Going on from a changed file would put the
      // start of one file and the end of another under one id.
      if (from != null && !source.isFingerprintOf(from)) throw RepositoryException.notFound;

      var unfinished = from;
      var passRefused = false;
      while (true) {
        final ticket = await _declare(path, mime, source.size, unfinished, onUnfinished);
        final received = ticket.received;
        if (received == null) {
          // A server older than phase 043: it cannot continue, so there is
          // nothing to remember, and the whole file goes.
          if (unfinished != null) await onUnfinished?.call(null);
          unfinished = null;
        } else if (unfinished?.fileId != ticket.fileId) {
          unfinished = UnfinishedUpload(fileId: ticket.fileId, sourceSize: source.size, sourceModifiedAt: source.modified);
          // Written down BEFORE the first byte: a restart in the middle of the
          // transfer has to find it.
          await onUnfinished?.call(unfinished);
        }
        final offset = received ?? 0;
        // A server claiming more than the file has is not one to send to.
        if (offset > source.size) throw RepositoryException.internal;
        logRepository.debug(target: this, message: 'file: upload ${ticket.fileId} from $offset of ${source.size}');
        // The share of the WHOLE file is known now, before a single new byte:
        // a ring that dropped to zero after every break would lie about it.
        onProgress?.call(source.size == 0 ? 1 : offset / source.size);

        try {
          await _remote.putBytes(
            uploadPath: ticket.uploadUrl,
            file: file,
            offset: offset,
            onProgress: onProgress == null ? null : (done, total) => onProgress(total == 0 ? 1 : done / total),
          );
        } on FileTransferException catch (e) {
          switch (e.failure) {
            case FileTransferFailure.passRejected:
              // A pass is one-shot and lives ten minutes, so it can be dead
              // before the first byte moves: the contract calls that routine
              // and says to ask for another, once. Twice in a row is the server
              // refusing, and the queue counts that.
              if (passRefused) throw RepositoryException.internal;
              passRefused = true;
              continue;
            case FileTransferFailure.sizeMismatch:
              // What was sent is not what was announced — announcing it again
              // fails identically, so this message is done.
              throw RepositoryException.invalidRequest;
            case FileTransferFailure.staleRange:
            case FileTransferFailure.connection:
              throw RepositoryException.connection;
          }
        }

        // The bytes went from the source as it was when this attempt began. If
        // it changed while they were going, the server holds a mix of two
        // files, and no message may name it.
        if (!(await _sourceOf(file)).isSameAs(source)) throw RepositoryException.notFound;
        // Only now is the id true: the bytes are on the server.
        return RepositoryResult<String>.success(data: ticket.fileId);
      }
    });
  }

  /// Declares the upload - or continues [unfinished] when there is one. A
  /// server that no longer has it (swept after a day, or it never got that far)
  /// is not an error for the person (FR-004): the upload starts over, and the
  /// handle is forgotten first, so a failure of the new declaration leaves
  /// nothing stale behind.
  Future<UploadTicketWireEntity> _declare(
    String path,
    String mime,
    int size,
    UnfinishedUpload? unfinished,
    Future<void> Function(UnfinishedUpload? upload)? onUnfinished,
  ) async {
    final name = _nameOf(path);
    if (unfinished != null) {
      final reply = await _remote.uploadBegin(name: name, sizeBytes: size, mime: mime, fileId: unfinished.fileId);
      final code = reply.error?.code;
      if (code == null || RepositoryException.fromWireCode(code) != RepositoryException.notFound) {
        return unwrapEnvelope(reply, 'uploadBegin');
      }
      logRepository.debug(target: this, message: 'file: upload ${unfinished.fileId} is gone from the server, starting over');
      await onUnfinished?.call(null);
    }
    return unwrapEnvelope(await _remote.uploadBegin(name: name, sizeBytes: size, mime: mime), 'uploadBegin');
  }

  /// The source's fingerprint. A file that is not there is `notFound`; so is
  /// one the platform will not describe - and that error is turned into the
  /// code HERE, because its message carries the path, the path carries the
  /// file's name, and execute() would write it into the log (FR-016).
  Future<_Source> _sourceOf(File file) async {
    try {
      final stat = await file.stat();
      if (stat.type == FileSystemEntityType.notFound) throw RepositoryException.notFound;
      return _Source(size: stat.size, modified: stat.modified);
    } on FileSystemException {
      throw RepositoryException.notFound;
    }
  }

  /// Downloads under way, by file id. ONE transfer per file: two would share
  /// the same `.part` file, the second deleting the first's bytes and the
  /// first renaming the second's still-growing file into place - a truncated
  /// picture at the final path, for good. The picture prefetch and the file
  /// view (5.3) both ask for the same file, so the second caller joins the
  /// first transfer and hears its progress from then on.
  final Map<String, _SharedDownload> _downloads = <String, _SharedDownload>{};

  @override
  Future<RepositoryResult<String>> download({
    required String fileId,
    required String suggestedName,
    int? expectedSize,
    TransferFraction? onProgress,
  }) {
    final running = _downloads[fileId];
    if (running != null) {
      if (onProgress != null) running.join(onProgress);
      return running.result;
    }
    final shared = _SharedDownload();
    if (onProgress != null) shared.join(onProgress);
    _downloads[fileId] = shared;
    shared.result = _downloadOnce(
      fileId: fileId,
      suggestedName: suggestedName,
      expectedSize: expectedSize,
      onProgress: shared.report,
    ).whenComplete(() => _downloads.remove(fileId));
    return shared.result;
  }

  Future<RepositoryResult<String>> _downloadOnce({
    required String fileId,
    required String suggestedName,
    required int? expectedSize,
    required TransferFraction onProgress,
  }) {
    return execute<String>(() async {
      final destination = File(await _cachePathFor(fileId, suggestedName));
      if (destination.existsSync()) return RepositoryResult<String>.success(data: destination.path);
      await destination.parent.create(recursive: true);

      // The bytes come into a SIDE file, renamed into place only once whole:
      // every reader, this method included, takes existence at the final path
      // as proof of completeness. Beside it, the version of the file those
      // bytes belong to - without it they could not be continued safely.
      final part = File('${destination.path}.part');
      final tag = File('${destination.path}.part.tag');
      var (offset, validator) = await _partOf(part, tag);

      var passRefused = false;
      var staleRetried = false;
      while (true) {
        final ticket = unwrapEnvelope(await _remote.downloadBegin(fileId: fileId), 'downloadBegin');
        final FetchedBytes fetched;
        try {
          fetched = await _remote.openBytes(downloadPath: ticket.downloadUrl, offset: offset, validator: validator);
        } on FileTransferException catch (e) {
          switch (e.failure) {
            case FileTransferFailure.passRejected:
              // Routine once - a pass is one-shot and short-lived; twice in a
              // row is the server refusing.
              if (passRefused) throw RepositoryException.internal;
              passRefused = true;
              continue;
            case FileTransferFailure.staleRange:
              // The bytes here are not shorter than the file there: some other
              // version of it. Start over at once; nothing anyone did is wrong.
              await _discard(part, tag);
              (offset, validator) = (0, null);
              if (staleRetried) throw RepositoryException.internal;
              staleRetried = true;
              continue;
            case FileTransferFailure.sizeMismatch:
              throw RepositoryException.invalidRequest;
            case FileTransferFailure.connection:
              throw RepositoryException.connection;
          }
        }

        // A file of another size is not the file this message names.
        if (expectedSize != null && expectedSize > 0 && fetched.total != expectedSize) {
          fetched.abandon();
          await _discard(part, tag);
          logRepository.debug(target: this, message: 'file: download $fileId is ${fetched.total} bytes, not $expectedSize');
          throw RepositoryException.internal;
        }
        if (fetched.whole) {
          // In THIS order: an empty part first, then the version, then the
          // bytes. A crash between any two leaves an empty part, or a part
          // holding only bytes of the version written beside it.
          await part.writeAsBytes(const <int>[], flush: true);
          offset = 0;
          await _writeTag(tag, fetched.validator);
        }
        logRepository.debug(target: this, message: 'file: download $fileId from $offset of ${fetched.total}');

        final total = fetched.total;
        var received = offset;
        onProgress(total == 0 ? 1 : received / total);
        final sink = part.openWrite(mode: FileMode.append);
        try {
          await for (final chunk in fetched.bytes) {
            sink.add(chunk);
            received += chunk.length;
            onProgress(total == 0 ? 1 : received / total);
          }
        } on FileTransferException {
          // What arrived stays: the next attempt asks only for the rest.
          throw RepositoryException.connection;
        } finally {
          await sink.flush();
          await sink.close();
        }
        // The server ended the body early; what came is kept for the next one.
        if (received < total) throw RepositoryException.connection;
        if (received > total) {
          await _discard(part, tag);
          throw RepositoryException.internal;
        }
        // The rename is the moment the file becomes real. Before it, nothing
        // that looks like a cache hit exists.
        await part.rename(destination.path);
        if (tag.existsSync()) await tag.delete();
        return RepositoryResult<String>.success(data: destination.path);
      }
    });
  }

  /// How much of the file is already here, and which version it belongs to. A
  /// part with no version written beside it cannot be checked against the
  /// server, so it is not continued.
  Future<(int, String?)> _partOf(File part, File tag) async {
    if (!part.existsSync()) {
      if (tag.existsSync()) await tag.delete();
      return (0, null);
    }
    final validator = tag.existsSync() ? (await tag.readAsString()).trim() : '';
    if (validator.isEmpty) {
      await _discard(part, tag);
      return (0, null);
    }
    return (await part.length(), validator);
  }

  /// The version beside the part, written whole or not at all.
  Future<void> _writeTag(File tag, String? validator) async {
    if (validator == null || validator.isEmpty) {
      // Nothing to name the version by: these bytes will not be continued.
      if (tag.existsSync()) await tag.delete();
      return;
    }
    final next = File('${tag.path}.next');
    await next.writeAsString(validator, flush: true);
    await next.rename(tag.path);
  }

  Future<void> _discard(File part, File tag) async {
    if (part.existsSync()) await part.delete();
    if (tag.existsSync()) await tag.delete();
  }

  @override
  Future<void> cancelTransfers() async => _remote.cancelTransfers();

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

/// One download and everyone waiting on it.
class _SharedDownload {
  late Future<RepositoryResult<String>> result;
  final List<TransferFraction> listeners = <TransferFraction>[];

  /// Where the download stands, so one who joins late is told at once rather
  /// than at the next chunk - which on a slow path can be a while.
  double? _last;

  void join(TransferFraction listener) {
    listeners.add(listener);
    final last = _last;
    if (last != null) listener(last);
  }

  void report(double fraction) {
    _last = fraction;
    for (final listener in List<TransferFraction>.of(listeners)) {
      listener(fraction);
    }
  }
}

/// What the upload knows about its source: enough to tell whether it is still
/// the file the bytes came from.
class _Source {
  const _Source({required this.size, required this.modified});

  final int size;
  final DateTime modified;

  bool isSameAs(_Source other) => size == other.size && _sameMillisecond(modified, other.modified);

  /// Compared to the millisecond, which is what the queue record keeps: the
  /// platform reports microseconds, and comparing those against a stored value
  /// would call every file "changed" after the first restart.
  bool isFingerprintOf(UnfinishedUpload upload) => size == upload.sourceSize && _sameMillisecond(modified, upload.sourceModifiedAt);

  static bool _sameMillisecond(DateTime a, DateTime b) => a.millisecondsSinceEpoch == b.millisecondsSinceEpoch;
}
