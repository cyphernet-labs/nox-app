import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/data/local/app_data_root.dart';
import 'package:nox_app/data/entity/file/upload_ticket_wire_entity.dart';
import 'package:nox_app/data/exception/file_transfer_exception.dart';
import 'package:nox_app/data/remote/datasource/file_remote_data_source.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/file/transfer_cancellation.dart';
import 'package:nox_app/domain/model/file/unfinished_upload.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';

/// The file chain over the data source (contract v0 §7).
///
/// Downloaded bytes live in a folder of the app's data folder named by file
/// id (phase 048: `AppDataRoot`). Not the database — Sembast is a document
/// store and blobs do not belong in it. Not the documents directory, which is
/// backed up and synced — the wrong promise for somebody else's picture; and
/// not the cache folder either, which the system may empty under a file the
/// thread still shows. Losing the folder costs one re-download.
@LazySingleton(as: FileRepository, env: [Environment.dev, Environment.prod, Environment.test])
class FileRepositoryImpl with BaseRepositoryHelper implements FileRepository {
  FileRepositoryImpl(this._remote, this._config);

  final FileRemoteDataSource _remote;
  final AppConfigRepository _config;

  /// How many changes of path one attempt goes on through by itself. A path
  /// that keeps changing under a transfer is a broken link after all, and the
  /// caller's pause is the better answer to that.
  static const int _pathChangeLimit = 5;

  /// Raised by [cancelTransfers] and [clean]: a download begun before either
  /// writes nothing to this device after it. Ending its transfer is not enough
  /// on its own - an attempt between two steps (asking for a pass, opening the
  /// bytes) has no transfer to end, and would go on to write into a cache just
  /// emptied for somebody else.
  int _epoch = 0;

  @override
  Future<RepositoryResult<String>> upload({
    required String path,
    required String mime,
    UnfinishedUpload? from,
    Future<void> Function(UnfinishedUpload? upload)? onUnfinished,
    TransferFraction? onProgress,
    TransferCancellation? cancellation,
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
      var pathChanges = 0;
      while (true) {
        // Thrown away while it waited its turn, or between two steps.
        if (cancellation?.isCancelled ?? false) throw RepositoryException.connection;
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
            cancellation: cancellation,
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
            case FileTransferFailure.pathChanged:
              // The path the bytes were going by is gone, and what arrived by
              // it stays on the server: the rest goes now, by the new one. A
              // pause first would only wait out a reason that no longer exists.
              if (++pathChanges > _pathChangeLimit) throw RepositoryException.connection;
              passRefused = false;
              continue;
            case FileTransferFailure.sizeMismatch:
              // What was sent is not what was announced — announcing it again
              // fails identically, so this message is done.
              throw RepositoryException.invalidRequest;
            case FileTransferFailure.sourceUnreadable:
              throw RepositoryException.notFound;
            case FileTransferFailure.serverError:
              // The server answered; one that keeps answering this way is
              // given up on as a refusing `message.send` is.
              throw RepositoryException.internal;
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
  /// one the platform will not describe, or will describe and not open - and
  /// that error is turned into the code HERE, because its message carries the
  /// path, the path carries the file's name, and execute() would write it into
  /// the log (FR-016).
  ///
  /// Opened, not only looked up: a sandbox forgets a picked file when the app
  /// restarts and still lets its size be read, so a fingerprint alone would
  /// declare an upload whose bytes can never be sent.
  Future<_Source> _sourceOf(File file) async {
    try {
      final stat = await file.stat();
      if (stat.type == FileSystemEntityType.notFound) throw RepositoryException.notFound;
      final probe = await file.open();
      await probe.close();
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
      final epoch = _epoch;
      void stillWanted() {
        if (_epoch != epoch) throw RepositoryException.connection;
      }

      final destination = File(await _cachePathFor(fileId, suggestedName));
      if (destination.existsSync()) return RepositoryResult<String>.success(data: destination.path);
      stillWanted();
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
      var pathChanges = 0;
      while (true) {
        final ticket = unwrapEnvelope(await _remote.downloadBegin(fileId: fileId), 'downloadBegin');
        stillWanted();
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
              stillWanted();
              await _discard(part, tag);
              (offset, validator) = (0, null);
              if (staleRetried) throw RepositoryException.internal;
              staleRetried = true;
              continue;
            case FileTransferFailure.pathChanged:
              // Asked by a path that is gone: ask again, now, by the new one.
              if (++pathChanges > _pathChangeLimit) throw RepositoryException.connection;
              passRefused = false;
              continue;
            case FileTransferFailure.sizeMismatch:
              throw RepositoryException.invalidRequest;
            case FileTransferFailure.serverError:
            case FileTransferFailure.sourceUnreadable:
              throw RepositoryException.internal;
            case FileTransferFailure.connection:
              throw RepositoryException.connection;
          }
        }
        if (_epoch != epoch) {
          fetched.abandon();
          throw RepositoryException.connection;
        }

        // A file of another size is not the file this message names.
        if (expectedSize != null && expectedSize > 0 && fetched.total != expectedSize) {
          fetched.abandon();
          await _discard(part, tag);
          logRepository.debug(target: this, message: 'file: download $fileId is ${fetched.total} bytes, not $expectedSize');
          throw RepositoryException.internal;
        }

        final total = fetched.total;
        var received = offset;
        var pathMoved = false;
        RandomAccessFile? out;
        try {
          if (fetched.whole) {
            // In THIS order: an empty part first, then the version, then the
            // bytes. A crash between any two leaves an empty part, or a part
            // holding only bytes of the version written beside it.
            await part.writeAsBytes(const <int>[], flush: true);
            received = 0;
            await _writeTag(tag, fetched.validator);
          }
          logRepository.debug(target: this, message: 'file: download $fileId from $received of $total');
          onProgress(total == 0 ? 1 : received / total);
          // Written chunk by chunk and awaited, not handed to a buffered sink:
          // a disk that refuses a write says so at that write, rather than
          // after the rest of the body has been read for nothing - and the
          // body waits for the disk instead of piling up in memory.
          out = await part.open(mode: FileMode.append);
          await for (final chunk in fetched.bytes) {
            try {
              await out.writeFrom(chunk);
            } on Object {
              fetched.abandon();
              rethrow;
            }
            received += chunk.length;
            onProgress(total == 0 ? 1 : received / total);
          }
        } on FileTransferException catch (e) {
          // What arrived stays: the next attempt asks only for the rest - and
          // when only the path changed, this one asks for it now.
          if (e.failure != FileTransferFailure.pathChanged || ++pathChanges > _pathChangeLimit) {
            throw RepositoryException.connection;
          }
          pathMoved = true;
        } on Object {
          // The disk refused the part, its version or a write before the body
          // was read: let the bytes go, or the connection stays open behind
          // an attempt that has already failed.
          fetched.abandon();
          rethrow;
        } finally {
          await out?.close();
        }
        if (pathMoved) {
          stillWanted();
          (offset, validator) = await _partOf(part, tag);
          passRefused = false;
          continue;
        }
        // The server ended the body early; what came is kept for the next one.
        if (received < total) throw RepositoryException.connection;
        if (received > total) {
          await _discard(part, tag);
          throw RepositoryException.internal;
        }
        // The rename is the moment the file becomes real. Before it, nothing
        // that looks like a cache hit exists.
        stillWanted();
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
  Future<void> cancelTransfers() async {
    _epoch++;
    _remote.cancelTransfers();
  }

  @override
  Future<String?> localPathFor({required String fileId, required String suggestedName}) async {
    final path = await _cachePathFor(fileId, suggestedName);
    return File(path).existsSync() ? path : null;
  }

  @override
  Future<String> cachePathFor({required String fileId, required String suggestedName}) => _cachePathFor(fileId, suggestedName);

  @override
  Future<void> clean() async {
    _epoch++;
    final dir = Directory(await AppDataRoot.pathOf(AppDataRoot.attachmentsFolder));
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  /// Keyed by file id, so two files that share a display name cannot collide;
  /// the name is kept only for the extension, which is what decoders sniff.
  Future<String> _cachePathFor(String fileId, String suggestedName) async {
    final folder = await AppDataRoot.pathOf(AppDataRoot.attachmentsFolder);
    final ext = suggestedName.contains('.') ? suggestedName.split('.').last : '';
    return '$folder${Platform.pathSeparator}$fileId${ext.isEmpty ? '' : '.$ext'}';
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

  /// Compared as an instant, to the millisecond - which is all the queue record
  /// keeps (milliseconds since the epoch, UTC). `DateTime ==` would also
  /// compare the time zone and whatever below a millisecond a platform reports,
  /// and call a file that never changed "changed" after a restart.
  bool isFingerprintOf(UnfinishedUpload upload) => size == upload.sourceSize && _sameMillisecond(modified, upload.sourceModifiedAt);

  static bool _sameMillisecond(DateTime a, DateTime b) => a.millisecondsSinceEpoch == b.millisecondsSinceEpoch;
}
