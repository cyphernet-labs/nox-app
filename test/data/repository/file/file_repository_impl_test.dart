import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/entity/base/error_wire_entity.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/file/upload_ticket_wire_entity.dart';
import 'package:nox_app/data/exception/file_transfer_exception.dart';
import 'package:nox_app/data/remote/datasource/file_remote_data_source.dart';
import 'package:nox_app/data/repository/file/file_repository_impl.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_app/domain/model/app_config/server_limits.dart';
import 'package:nox_app/domain/model/file/unfinished_upload.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/log_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A data source the test drives: it records what it was asked, and can refuse
/// the way the real server refuses.
class _FakeSource implements FileRemoteDataSource {
  int begins = 0;
  int puts = 0;
  String? beginErrorCode;
  String? downloadErrorCode;
  List<int> bytesToReturn = const [1, 2, 3, 4];
  bool truncateDownload = false;
  int downloadBegins = 0;

  /// Holds a download half-way, after its first bytes are on disk.
  Completer<void>? holdDownload;

  /// Answers like a server older than phase 043: no `received`, no continuing.
  bool oldServer = false;

  /// What the server holds of each upload it knows, by file id.
  final Map<String, int> held = <String, int>{};

  /// Every declaration's `file_id`, in order - null for a new upload.
  final List<String?> continued = <String?>[];

  /// Every PUT's offset, in order.
  final List<int> offsets = <int>[];

  /// What happened, in order: `put:<offset>` here, `noted:<id>` from the test's
  /// listener. Order is the point - the handle has to be written down before
  /// the first byte moves.
  final List<String> log = <String>[];

  /// Failures for the coming PUTs, one each, in order.
  final List<FileTransferFailure> putFailures = <FileTransferFailure>[];

  /// Runs in the middle of a PUT, before it ends.
  Future<void> Function()? duringPut;

  @override
  Future<ResponseEntity<UploadTicketWireEntity>> uploadBegin({
    required String name,
    required int sizeBytes,
    required String mime,
    String? fileId,
  }) async {
    begins++;
    continued.add(fileId);
    final code = beginErrorCode;
    if (code != null) return _refused(code);
    if (fileId != null && !oldServer) {
      final has = held[fileId];
      if (has == null) return _refused('not_found');
      return _ticket(fileId, has);
    }
    final id = 'f_$begins';
    held[id] = 0;
    return _ticket(id, oldServer ? null : 0);
  }

  @override
  Future<void> putBytes({required String uploadPath, required File file, required int offset, TransferProgress? onProgress}) async {
    puts++;
    offsets.add(offset);
    log.add('put:$offset');
    await duringPut?.call();
    if (putFailures.isNotEmpty) throw FileTransferException(putFailures.removeAt(0));
    final total = await file.length();
    onProgress?.call(total, total);
    held[uploadPath.substring('/files/pass_'.length)] = total;
  }

  ResponseEntity<UploadTicketWireEntity> _ticket(String id, int? received) => ResponseEntity<UploadTicketWireEntity>(
    success: true,
    data: UploadTicketWireEntity(
      fileId: id,
      uploadUrl: '/files/pass_$id',
      uploadToken: 'pass_$id',
      maxAttachmentBytes: 104857600,
      received: received,
    ),
  );

  ResponseEntity<UploadTicketWireEntity> _refused(String code) => ResponseEntity<UploadTicketWireEntity>(
    success: false,
    error: ErrorWireEntity(code: code, message: code),
  );

  @override
  Future<ResponseEntity<DownloadTicketWireEntity>> downloadBegin({required String fileId}) async {
    downloadBegins++;
    final code = downloadErrorCode;
    if (code != null) {
      return ResponseEntity<DownloadTicketWireEntity>(
        success: false,
        error: ErrorWireEntity(code: code, message: code),
      );
    }
    return const ResponseEntity<DownloadTicketWireEntity>(
      success: true,
      data: DownloadTicketWireEntity(downloadUrl: '/files/get', downloadToken: 'get'),
    );
  }

  @override
  Future<void> getBytes({required String downloadPath, required File destination, TransferProgress? onProgress}) async {
    // Dio writes straight to the path it is handed, so the repository is
    // responsible for making a torn transfer invisible. Reproduce both halves:
    // some bytes land, then it fails.
    final hold = holdDownload;
    if (hold != null) {
      destination.writeAsBytesSync(bytesToReturn.take(1).toList());
      onProgress?.call(1, bytesToReturn.length);
      await hold.future;
    }
    destination.writeAsBytesSync(truncateDownload ? bytesToReturn.take(1).toList() : bytesToReturn);
    if (truncateDownload) throw const FileTransferException(FileTransferFailure.connection);
    onProgress?.call(bytesToReturn.length, bytesToReturn.length);
  }

  int cancels = 0;

  @override
  void cancelTransfers() => cancels++;
}

void main() {
  late _FakeSource source;
  late FileRepositoryImpl repository;
  late File file;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    final config = getIt<AppConfigRepository>();
    await config.initialize(flavorType: AppFlavorType.stage);
    source = _FakeSource();
    repository = FileRepositoryImpl(source, config);
    file = File('${Directory.systemTemp.path}/nox_repo_${DateTime.now().microsecondsSinceEpoch}.bin')..writeAsBytesSync([1, 2, 3, 4]);
    await repository.clean();
  });

  tearDown(() async {
    if (file.existsSync()) file.deleteSync();
    await repository.clean();
    await getIt.reset();
  });

  group('upload', () {
    Future<UnfinishedUpload> fingerprintOf(File f, String fileId) async {
      final stat = await f.stat();
      // Stored to the millisecond, as the queue record keeps it.
      return UnfinishedUpload(
        fileId: fileId,
        sourceSize: stat.size,
        sourceModifiedAt: DateTime.fromMillisecondsSinceEpoch(stat.modified.millisecondsSinceEpoch),
      );
    }

    test('the id comes back only after the bytes are confirmed', () async {
      final result = await repository.upload(path: file.path, mime: 'application/octet-stream');

      expect(result.data, 'f_1');
      expect(source.begins, 1);
      expect(source.puts, 1);
    });

    test('a new upload is written down before its first byte moves', () async {
      // A restart in the middle of the PUT has to find the upload, or it starts
      // from the first byte again - the very thing this phase removes.
      final heard = <UnfinishedUpload?>[];
      final result = await repository.upload(
        path: file.path,
        mime: 'application/octet-stream',
        onUnfinished: (upload) async {
          heard.add(upload);
          source.log.add('noted:${upload?.fileId}');
        },
      );

      expect(result.data, 'f_1');
      expect(source.log, ['noted:f_1', 'put:0']);
      final stat = await file.stat();
      expect(heard.single?.sourceSize, stat.size);
      expect(heard.single?.sourceModifiedAt.millisecondsSinceEpoch, stat.modified.millisecondsSinceEpoch);
    });

    test('a continued upload sends only what the server does not have, and its share starts there', () async {
      file.writeAsBytesSync(List<int>.filled(1000, 7));
      final from = await fingerprintOf(file, 'f_77');
      source.held['f_77'] = 400;
      final shares = <double>[];

      final result = await repository.upload(path: file.path, mime: 'application/octet-stream', from: from, onProgress: shares.add);

      expect(result.data, 'f_77');
      expect(source.continued, ['f_77']);
      expect(source.offsets, [400], reason: 'the bytes the server holds are not sent again (FR-001)');
      expect(shares.first, 0.4, reason: 'the ring shows the whole file, not a fresh start (FR-012)');
      expect(shares.last, 1.0);
    });

    test('a fingerprint kept to the millisecond still matches the source after a restart', () async {
      // The platform reports microseconds and the record keeps milliseconds:
      // compared exactly, every file would look changed after a restart.
      final from = await fingerprintOf(file, 'f_77');
      source.held['f_77'] = 2;

      final result = await repository.upload(path: file.path, mime: 'application/octet-stream', from: from);

      expect(result.data, 'f_77');
    });

    test('an upload the server no longer has starts over in the same attempt, without an error (FR-004)', () async {
      final from = await fingerprintOf(file, 'f_swept');
      final heard = <UnfinishedUpload?>[];

      final result = await repository.upload(
        path: file.path,
        mime: 'application/octet-stream',
        from: from,
        onUnfinished: (upload) async => heard.add(upload),
      );

      expect(result.data, 'f_2', reason: 'a new upload, under the id the server gave it');
      expect(source.continued, ['f_swept', null]);
      expect(heard.map((u) => u?.fileId), [null, 'f_2'], reason: 'the dead handle is forgotten, the new one written down');
      expect(source.offsets, [0]);
    });

    test('a source that changed since the upload began is not continued', () async {
      final from = await fingerprintOf(file, 'f_77');
      source.held['f_77'] = 2;
      file.writeAsBytesSync([1, 2, 3, 4, 5, 6]); // another size: another file

      final result = await repository.upload(path: file.path, mime: 'application/octet-stream', from: from);

      expect(result.exception, RepositoryException.notFound);
      expect(source.begins, 0, reason: 'nothing of another file may go under this id');
    });

    test('a source changed with its size kept is caught by its modification time', () async {
      final stat = await file.stat();
      final from = UnfinishedUpload(
        fileId: 'f_77',
        sourceSize: stat.size,
        sourceModifiedAt: stat.modified.subtract(const Duration(seconds: 5)),
      );
      source.held['f_77'] = 2;

      final result = await repository.upload(path: file.path, mime: 'application/octet-stream', from: from);

      expect(result.exception, RepositoryException.notFound);
    });

    test('a source that changes while its bytes are going makes no id, even when the PUT succeeded', () async {
      // The server would hold the start of one file and the end of another;
      // no message may name that.
      source.duringPut = () async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        file.writeAsBytesSync([9, 9, 9, 9, 9]);
      };

      final result = await repository.upload(path: file.path, mime: 'application/octet-stream');

      expect(result.exception, RepositoryException.notFound);
    });

    test('a server that cannot continue gets the whole file, and nothing is written down', () async {
      source.oldServer = true;
      final from = await fingerprintOf(file, 'f_77');
      final heard = <UnfinishedUpload?>[];

      final result = await repository.upload(
        path: file.path,
        mime: 'application/octet-stream',
        from: from,
        onUnfinished: (upload) async => heard.add(upload),
      );

      expect(result.data, 'f_1', reason: 'an old server ignores file_id and declares a new file (FR-005)');
      expect(source.offsets, [0]);
      expect(heard, [null], reason: 'a handle it cannot use is forgotten');
    });

    test('a rejected pass on a server that continues asks again for the SAME file', () async {
      // The contract calls a burnt pass routine: ask for another. Asking with a
      // new declaration would throw away what the server already has.
      source.putFailures.add(FileTransferFailure.passRejected);

      final result = await repository.upload(path: file.path, mime: 'application/octet-stream');

      expect(result.data, 'f_1');
      expect(source.continued, [null, 'f_1']);
    });

    test('a rejected pass on an older server is retried once with a NEW declaration', () async {
      source.oldServer = true;
      source.putFailures.add(FileTransferFailure.passRejected);

      final result = await repository.upload(path: file.path, mime: 'application/octet-stream');

      expect(result.data, 'f_2', reason: 'the second declaration issued a new id');
      expect(source.begins, 2, reason: 'a new pass was requested rather than the burnt one reused');
    });

    test('two rejected passes in a row are the server refusing: internal, which the queue counts', () async {
      source.putFailures.addAll([FileTransferFailure.passRejected, FileTransferFailure.passRejected]);

      final result = await repository.upload(path: file.path, mime: 'application/octet-stream');

      expect(result.exception, RepositoryException.internal);
      expect(source.begins, 2);
    });

    test('everything already on the server is finished with an empty PUT, then the id', () async {
      final from = await fingerprintOf(file, 'f_77');
      source.held['f_77'] = await file.length();

      final result = await repository.upload(path: file.path, mime: 'application/octet-stream', from: from);

      expect(result.data, 'f_77');
      expect(source.offsets, [await file.length()], reason: 'the PUT carries nothing, and completes the upload');
    });

    test('a broken transfer is a connection failure, to be continued', () async {
      source.putFailures.add(FileTransferFailure.connection);

      final result = await repository.upload(path: file.path, mime: 'application/octet-stream');

      expect(result.exception, RepositoryException.connection);
    });

    test('a size mismatch is terminal — announcing the same file again fails the same way', () async {
      source.putFailures.add(FileTransferFailure.sizeMismatch);

      final result = await repository.upload(path: file.path, mime: 'application/octet-stream');

      expect(result.exception, RepositoryException.invalidRequest);
      expect(source.begins, 1, reason: 'no point asking for another pass');
    });

    test('a file that is gone from disk fails before anything is declared, and its path is never logged', () async {
      final lines = <String>[];
      getIt.allowReassignment = true;
      getIt.registerSingleton<LogRepository>(_CapturingLog(lines));
      file.deleteSync();

      final result = await repository.upload(path: file.path, mime: 'application/octet-stream');

      expect(result.exception, RepositoryException.notFound);
      expect(source.begins, 0, reason: 'nothing to declare');
      expect(lines.where((line) => line.contains(file.path)), isEmpty, reason: 'the path carries the file name (FR-016)');
    });

    test('a file over the limit is refused before a byte moves (FR-013)', () async {
      final big = File('${Directory.systemTemp.path}/nox_big_${DateTime.now().microsecondsSinceEpoch}.bin')
        ..writeAsBytesSync(List<int>.filled(64, 1));
      addTearDown(() => big.existsSync() ? big.deleteSync() : null);
      final config = getIt<AppConfigRepository>()
        ..updateLimits(const ServerLimits(maxMessageBytes: 65536, maxAttachmentBytes: 8, maxFrameBytes: 131072));

      final result = await FileRepositoryImpl(source, config).upload(path: big.path, mime: 'application/octet-stream');

      expect(result.exception, RepositoryException.payloadTooLarge);
      expect(source.begins, 0);
    });
  });

  group('download', () {
    test('the bytes land in the cache and the path comes back', () async {
      final result = await repository.download(fileId: 'f_1', suggestedName: 'x.bin');

      expect(result.hasData, isTrue);
      expect(File(result.data!).readAsBytesSync(), [1, 2, 3, 4]);
    });

    test('two callers asking for the same file share ONE transfer, and both hear its progress', () async {
      // The picture prefetch and the file view ask for the same file. Two
      // transfers shared one `.part` file: the second deleted the first's
      // bytes, and the first renamed a still-growing file into place.
      source.holdDownload = Completer<void>();
      final heardByPrefetch = <double>[];
      final heardByFileView = <double>[];

      final first = repository.download(fileId: 'f_same', suggestedName: 'photo.png', onProgress: heardByPrefetch.add);
      await pumpEventQueue();
      final second = repository.download(fileId: 'f_same', suggestedName: 'photo.png', onProgress: heardByFileView.add);
      source.holdDownload!.complete();
      final results = await Future.wait([first, second]);

      expect(source.downloadBegins, 1);
      expect(results.map((r) => r.data).toSet(), hasLength(1));
      expect(File(results.first.data!).readAsBytesSync(), [1, 2, 3, 4], reason: 'the whole file, not a torn one');
      expect(heardByPrefetch.last, 1.0);
      expect(heardByFileView.last, 1.0, reason: 'the caller who joined hears the rest of the transfer');
    });

    test('a later download of the same file is a new transfer, not the finished one', () async {
      await repository.download(fileId: 'f_again', suggestedName: 'a.bin');
      await repository.clean();

      await repository.download(fileId: 'f_again', suggestedName: 'a.bin');

      expect(source.downloadBegins, 2);
    });

    test('a torn transfer leaves NOTHING that looks like a cache hit', () async {
      // The defect this guards: a half file sitting where a whole one belongs is
      // served forever as complete, and nothing ever tries again.
      source.truncateDownload = true;

      final failed = await repository.download(fileId: 'f_1', suggestedName: 'x.bin');
      expect(failed.hasData, isFalse);
      expect(await repository.localPathFor(fileId: 'f_1', suggestedName: 'x.bin'), isNull);

      // And a later, working attempt gets the whole file.
      source.truncateDownload = false;
      final second = await repository.download(fileId: 'f_1', suggestedName: 'x.bin');
      expect(File(second.data!).readAsBytesSync(), [1, 2, 3, 4]);
    });

    test('bytes the server no longer holds are a terminal refusal, not a retryable one', () async {
      source.downloadErrorCode = 'attachment_gone';

      final result = await repository.download(fileId: 'f_1', suggestedName: 'x.bin');

      expect(result.exception, RepositoryException.attachmentGone);
    });

    test('a file the server never heard of is terminal too', () async {
      source.downloadErrorCode = 'not_found';

      final result = await repository.download(fileId: 'f_1', suggestedName: 'x.bin');

      expect(result.exception, RepositoryException.notFound);
    });

    test('clean removes the cache, so logout leaves no pictures behind', () async {
      await repository.download(fileId: 'f_1', suggestedName: 'x.bin');
      expect(await repository.localPathFor(fileId: 'f_1', suggestedName: 'x.bin'), isNotNull);

      await repository.clean();

      expect(await repository.localPathFor(fileId: 'f_1', suggestedName: 'x.bin'), isNull);
    });
  });
}

/// Records what the app writes, so a test can assert what it does NOT write.
class _CapturingLog implements LogRepository {
  _CapturingLog(this.lines);

  final List<String> lines;

  @override
  void debug({Object? target, required String message}) => lines.add(message);

  @override
  void error({Object? target, required Object error, StackTrace? stackTrace}) => lines.add(error.toString());
}
