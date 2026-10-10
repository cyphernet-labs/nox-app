import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/entity/base/error_wire_entity.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/file/upload_ticket_wire_entity.dart';
import 'package:nox_app/data/exception/file_transfer_exception.dart';
import 'package:nox_app/data/local/app_data_root.dart';
import 'package:nox_app/data/local/device_vault.dart';
import 'package:nox_app/data/local/sealed_file.dart';
import 'package:nox_app/data/remote/datasource/file_remote_data_source.dart';
import 'package:nox_app/data/repository/file/file_repository_impl.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_app/domain/model/app_config/server_limits.dart';
import 'package:nox_app/domain/model/file/transfer_cancellation.dart';
import 'package:nox_app/domain/model/file/unfinished_upload.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/log_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/sealed_files.dart';

/// A data source the test drives: it records what it was asked, and can refuse
/// the way the real server refuses.
class _FakeSource implements FileRemoteDataSource {
  int begins = 0;
  int puts = 0;
  String? beginErrorCode;
  String? downloadErrorCode;
  List<int> bytesToReturn = const [1, 2, 3, 4];
  int downloadBegins = 0;

  /// Holds a download half-way, after its first byte is on disk.
  Completer<void>? holdDownload;

  /// The version of the file "the server" holds - its Last-Modified.
  String serverVersion = 'v1';

  /// The next GET breaks after this many bytes of its body...
  int? breakAfter;

  /// ...the way this says: a broken link, or a path that changed under it.
  FileTransferFailure breakWith = FileTransferFailure.connection;

  /// Holds the next download's request for a pass until completed.
  Completer<void>? holdBegin;

  /// Failures for the coming GETs, one each, in order.
  final List<FileTransferFailure> getFailures = <FileTransferFailure>[];

  /// A size to claim instead of the real one: another file under this id.
  int? claimedTotal;

  /// Every GET's offset and the version it named.
  final List<(int, String?)> gets = <(int, String?)>[];

  /// Runs as the first byte of a body is handed over.
  void Function()? onFirstBytes;

  int abandoned = 0;

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

  /// What every PUT carried, and the size it declared - the plain bytes and
  /// the plain length, whatever the source is on the disk (phase 048).
  final List<List<int>> bodies = <List<int>>[];
  final List<int> sizes = <int>[];

  @override
  Future<void> putBytes({
    required String uploadPath,
    required int size,
    required int offset,
    required Stream<List<int>> body,
    TransferProgress? onProgress,
    TransferCancellation? cancellation,
  }) async {
    puts++;
    offsets.add(offset);
    log.add('put:$offset');
    await duringPut?.call();
    if (putFailures.isNotEmpty) throw FileTransferException(putFailures.removeAt(0));
    // As the real source does: a body that breaks is the source failing.
    try {
      bodies.add([await for (final chunk in body) ...chunk]);
    } on Object {
      throw const FileTransferException(FileTransferFailure.sourceUnreadable);
    }
    sizes.add(size);
    onProgress?.call(size, size);
    held[uploadPath.substring('/files/pass_'.length)] = size;
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
    final held = holdBegin;
    holdBegin = null;
    if (held != null) await held.future;
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
  Future<FetchedBytes> openBytes({required String downloadPath, required int offset, String? validator}) async {
    gets.add((offset, validator));
    if (getFailures.isNotEmpty) throw FileTransferException(getFailures.removeAt(0));
    // The rest only for bytes of the version the server holds - If-Range.
    final rest = offset > 0 && validator == serverVersion;
    if (rest && offset >= bytesToReturn.length) throw const FileTransferException(FileTransferFailure.staleRange);
    final body = bytesToReturn.sublist(rest ? offset : 0);
    final cut = breakAfter;
    breakAfter = null;
    final cutWith = breakWith;
    breakWith = FileTransferFailure.connection;
    final hold = holdDownload;
    Stream<List<int>> bytes() async* {
      onFirstBytes?.call();
      if (hold != null) {
        yield body.sublist(0, 1);
        await hold.future;
        yield body.sublist(1);
        return;
      }
      if (cut != null) {
        yield body.sublist(0, cut);
        throw FileTransferException(cutWith);
      }
      yield body;
    }

    return FetchedBytes(
      whole: !rest,
      total: claimedTotal ?? bytesToReturn.length,
      validator: serverVersion,
      bytes: bytes(),
      abandon: () => abandoned++,
    );
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
    repository = FileRepositoryImpl(source, config, getIt<DeviceVault>());
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

    test('a fingerprint is the same instant to the millisecond, however it is written down', () async {
      // The record keeps milliseconds since the epoch, in UTC. `DateTime ==`
      // compares the time zone too, and anything below a millisecond a
      // platform reports: compared that way, a file that never changed would
      // look changed after a restart.
      final stat = await file.stat();
      final ms = stat.modified.millisecondsSinceEpoch;
      source.held['f_77'] = 2;

      final inUtc = await repository.upload(
        path: file.path,
        mime: 'application/octet-stream',
        from: UnfinishedUpload(
          fileId: 'f_77',
          sourceSize: stat.size,
          sourceModifiedAt: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
        ),
      );
      source.held['f_77'] = 2;
      final finer = await repository.upload(
        path: file.path,
        mime: 'application/octet-stream',
        from: UnfinishedUpload(
          fileId: 'f_77',
          sourceSize: stat.size,
          sourceModifiedAt: DateTime.fromMicrosecondsSinceEpoch(ms * 1000 + 600),
        ),
      );

      expect(inUtc.data, 'f_77');
      expect(finer.data, 'f_77');
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

    test('a file that is there but cannot be read fails before anything is declared, and its path is never logged', () async {
      // A sandbox forgets a picked file when the app restarts and still lets
      // its size be read: fingerprinted alone, it was declared, and its bytes
      // then failed as a broken link would - for good, holding the queue.
      final lines = <String>[];
      getIt.allowReassignment = true;
      getIt.registerSingleton<LogRepository>(_CapturingLog(lines));
      Process.runSync('chmod', ['000', file.path]);
      addTearDown(() => Process.runSync('chmod', ['644', file.path]));
      try {
        await file.open().then((f) => f.close());
        markTestSkipped('this user can read a file nobody may read');
        return;
      } on FileSystemException {
        // As it should be.
      }

      final result = await repository.upload(path: file.path, mime: 'application/octet-stream');

      expect(result.exception, RepositoryException.notFound, reason: 'terminal: no retry reads it');
      expect(source.begins, 0);
      expect(lines.where((line) => line.contains(file.path)), isEmpty, reason: 'FR-016');
    });

    test('a source that stops being readable once the upload is under way is notFound too', () async {
      source.putFailures.add(FileTransferFailure.sourceUnreadable);

      final result = await repository.upload(path: file.path, mime: 'application/octet-stream');

      expect(result.exception, RepositoryException.notFound);
    });

    test('a server answering with what the contract does not name is internal, which the queue counts', () async {
      source.putFailures.add(FileTransferFailure.serverError);

      final result = await repository.upload(path: file.path, mime: 'application/octet-stream');

      expect(result.exception, RepositoryException.internal);
    });

    test('a change of path under the bytes is no failure: the rest goes at once, in the same call (FR-008)', () async {
      // Whatever arrived by the old path stays on the server; a pause before
      // going on would wait out a reason that no longer exists.
      source.duringPut = () async => source.held['f_1'] = 2;
      source.putFailures.add(FileTransferFailure.pathChanged);

      final result = await repository.upload(path: file.path, mime: 'application/octet-stream');

      expect(result.data, 'f_1');
      expect(source.continued, [null, 'f_1'], reason: 'the same upload, continued');
      expect(source.offsets, [0, 2], reason: 'from what the server had');
    });

    test('a path that keeps changing is a broken link after all', () async {
      source.putFailures.addAll(List<FileTransferFailure>.filled(10, FileTransferFailure.pathChanged));

      final result = await repository.upload(path: file.path, mime: 'application/octet-stream');

      expect(result.exception, RepositoryException.connection, reason: 'the caller pauses, and nothing is counted');
      expect(source.puts, lessThan(10));
    });

    test('an upload thrown away before its bytes go sends none of them', () async {
      final result = await repository.upload(
        path: file.path,
        mime: 'application/octet-stream',
        cancellation: TransferCancellation()..cancel(),
      );

      expect(result.exception, RepositoryException.connection);
      expect(source.puts, 0);
    });

    group("the queue's sealed copy (phase 048)", () {
      final plain = List<int>.generate(100000, (i) => (i * 3 + i ~/ 777) & 0xFF);
      late File sealed;

      setUp(() async {
        sealed = await writeSealed('${Directory.systemTemp.path}/nox_sealed_up_${DateTime.now().microsecondsSinceEpoch}', plain);
      });

      tearDown(() => sealed.existsSync() ? sealed.deleteSync() : null);

      test('goes up as its plain bytes, its plain length declared', () async {
        final result = await repository.upload(path: sealed.path, mime: 'application/octet-stream');

        expect(result.data, 'f_1');
        expect(source.sizes.single, plain.length, reason: 'the server is told the file, not what the device keeps');
        expect(source.bodies.single, plain);
      });

      test('is continued from the middle of a chunk, and only the rest goes (phase 043)', () async {
        final stat = await sealed.stat();
        final from = UnfinishedUpload(
          fileId: 'f_77',
          sourceSize: plain.length,
          sourceModifiedAt: DateTime.fromMillisecondsSinceEpoch(stat.modified.millisecondsSinceEpoch),
        );
        source.held['f_77'] = 70000;

        final result = await repository.upload(path: sealed.path, mime: 'application/octet-stream', from: from);

        expect(result.data, 'f_77');
        expect(source.offsets, [70000]);
        expect(source.bodies.single, plain.sublist(70000));
      });

      test('cut short, it is gone for good: nothing is declared', () async {
        final bytes = sealed.readAsBytesSync();
        sealed.writeAsBytesSync(bytes.sublist(0, SealedFile.headerLength + SealedFile.sealedChunkLength + 5));

        final result = await repository.upload(path: sealed.path, mime: 'application/octet-stream');

        expect(result.exception, RepositoryException.notFound);
        expect(source.begins, 0);
      });

      test('a chunk changed on the disk ends the upload as an unreadable source, which no retry sends', () async {
        final bytes = sealed.readAsBytesSync()..[SealedFile.headerLength + SealedFile.sealedChunkLength + 9] ^= 0x01;
        sealed.writeAsBytesSync(bytes);

        final result = await repository.upload(path: sealed.path, mime: 'application/octet-stream');

        expect(result.exception, RepositoryException.notFound);
      });
    });

    test('a file over the limit is refused before a byte moves (FR-013)', () async {
      final big = File('${Directory.systemTemp.path}/nox_big_${DateTime.now().microsecondsSinceEpoch}.bin')
        ..writeAsBytesSync(List<int>.filled(64, 1));
      addTearDown(() => big.existsSync() ? big.deleteSync() : null);
      final config = getIt<AppConfigRepository>()
        ..updateLimits(const ServerLimits(maxMessageBytes: 65536, maxAttachmentBytes: 8, maxFrameBytes: 131072));

      final result = await FileRepositoryImpl(
        source,
        config,
        getIt<DeviceVault>(),
      ).upload(path: big.path, mime: 'application/octet-stream');

      expect(result.exception, RepositoryException.payloadTooLarge);
      expect(source.begins, 0);
    });
  });

  group('download', () {
    Future<File> cached(String fileId, String ext) async => File('${await AppDataRoot.pathOf(AppDataRoot.attachmentsFolder)}/$fileId.$ext');

    /// The plain bytes of what is on the disk: every file there is sealed.
    Future<List<int>> plainOf(String path) async => (await SealedReader.open(File(path)))!.readAll();

    /// Two and a half chunks: a break can leave whole chunks behind.
    final big = List<int>.generate(2 * SealedFile.chunkSize + 32768, (i) => (i * 7 + i ~/ 1000) & 0xFF);

    test('the bytes land in the cache, sealed, and the path comes back', () async {
      source.bytesToReturn = [...'NOX-MARKER'.codeUnits, ...big];
      final result = await repository.download(fileId: 'f_1', suggestedName: 'x.bin');

      expect(result.hasData, isTrue);
      expect(await plainOf(result.data!), source.bytesToReturn);
      expect(String.fromCharCodes(File(result.data!).readAsBytesSync()), isNot(contains('NOX-MARKER')), reason: 'FR-005');
    });

    test('a broken download keeps the whole chunks that arrived, sealed, and the version they belong to', () async {
      source
        ..bytesToReturn = big
        ..breakAfter = 100000;

      final failed = await repository.download(fileId: 'f_1', suggestedName: 'x.bin', expectedSize: big.length);

      expect(failed.exception, RepositoryException.connection);
      final destination = await cached('f_1', 'bin');
      expect(destination.existsSync(), isFalse, reason: 'nothing that looks like a cache hit');
      final part = File('${destination.path}.part');
      // One whole chunk: the 34464 bytes after it were held in memory, never
      // sealed - a chunk is sealed only once it is whole.
      expect(part.lengthSync(), SealedFile.headerLength + SealedFile.sealedChunkLength);
      expect(await SealedFile.isSealed(part), isTrue);
      expect(File('${destination.path}.part.tag').readAsStringSync(), 'v1');
    });

    test(
      'the next attempt asks only for the rest from the last whole chunk - after a restart too - and appends it (FR-006, FR-007)',
      () async {
        source
          ..bytesToReturn = big
          ..breakAfter = 100000;
        await repository.download(fileId: 'f_1', suggestedName: 'x.bin', expectedSize: big.length);
        final shares = <double>[];

        // A new repository over the same cache: the process was restarted.
        final restarted = FileRepositoryImpl(source, getIt<AppConfigRepository>(), getIt<DeviceVault>());
        final result = await restarted.download(fileId: 'f_1', suggestedName: 'x.bin', expectedSize: big.length, onProgress: shares.add);

        expect(source.gets.last, (SealedFile.chunkSize, 'v1'), reason: 'only the missing bytes, for the version already here');
        expect(await plainOf(result.data!), big);
        expect(shares.first, SealedFile.chunkSize / big.length, reason: 'the share of the whole file (FR-012)');
        expect(File('${result.data!}.part.tag').existsSync(), isFalse);
      },
    );

    test('a chunk a crash wrote half-way is cut off, and asked for again', () async {
      source
        ..bytesToReturn = big
        ..breakAfter = 2 * SealedFile.chunkSize + 10;
      await repository.download(fileId: 'f_1', suggestedName: 'x.bin');
      final part = File('${(await cached('f_1', 'bin')).path}.part');
      part.writeAsBytesSync(List<int>.filled(500, 0xEE), mode: FileMode.append);

      final result = await repository.download(fileId: 'f_1', suggestedName: 'x.bin');

      expect(source.gets.last, (2 * SealedFile.chunkSize, 'v1'));
      expect(await plainOf(result.data!), big);
    });

    test('another version on the server starts the file over under a new id, its version written before its first byte', () async {
      source
        ..bytesToReturn = big
        ..breakAfter = 100000;
      await repository.download(fileId: 'f_1', suggestedName: 'x.bin');
      final destination = await cached('f_1', 'bin');
      final idBefore = File('${destination.path}.part').readAsBytesSync().sublist(12, 28);
      source
        ..serverVersion = 'v2'
        ..bytesToReturn = List<int>.generate(1000, (i) => 255 - (i & 0xFF));
      String? tagAtFirstByte;
      List<int>? partAtFirstByte;
      source.onFirstBytes = () {
        tagAtFirstByte = File('${destination.path}.part.tag').readAsStringSync();
        partAtFirstByte = File('${destination.path}.part').readAsBytesSync();
      };

      final result = await repository.download(fileId: 'f_1', suggestedName: 'x.bin');

      expect(tagAtFirstByte, 'v2', reason: 'a crash now leaves only bytes of the version beside them');
      expect(partAtFirstByte, hasLength(SealedFile.headerLength), reason: 'none of the old version left in the part');
      expect(partAtFirstByte!.sublist(12, 28), isNot(idBefore), reason: 'other bytes never go under an id used before');
      expect(await plainOf(result.data!), source.bytesToReturn);
    });

    test('a part no shorter than the file there is thrown away, and the file comes again from the start', () async {
      source.bytesToReturn = big.sublist(0, SealedFile.chunkSize);
      final destination = await cached('f_1', 'bin');
      // Three whole chunks of some earlier, longer version.
      final writer = await SealedWriter.create(File('${destination.path}.part'), total: 4 * SealedFile.chunkSize);
      await writer.add(big.sublist(0, 2 * SealedFile.chunkSize));
      await writer.add(big.sublist(0, SealedFile.chunkSize));
      await writer.close();
      File('${destination.path}.part.tag').writeAsStringSync('v1');

      final result = await repository.download(fileId: 'f_1', suggestedName: 'x.bin');

      expect(source.gets, [(3 * SealedFile.chunkSize, 'v1'), (0, null)]);
      expect(await plainOf(result.data!), source.bytesToReturn);
    });

    test('a part that is no sealed part is not continued: a plain one left by a build before phase 048', () async {
      final destination = await cached('f_1', 'bin');
      await destination.parent.create(recursive: true);
      File('${destination.path}.part').writeAsBytesSync([1, 2, 3, 4, 5]);
      File('${destination.path}.part.tag').writeAsStringSync('v1');

      final result = await repository.download(fileId: 'f_1', suggestedName: 'x.bin');

      expect(source.gets, [(0, null)]);
      expect(await plainOf(result.data!), [1, 2, 3, 4]);
    });

    test('a part whose version nobody wrote down is not continued', () async {
      final destination = await cached('f_1', 'bin');
      await destination.parent.create(recursive: true);
      File('${destination.path}.part').writeAsBytesSync([7, 7]);

      final result = await repository.download(fileId: 'f_1', suggestedName: 'x.bin');

      expect(source.gets, [(0, null)]);
      expect(await plainOf(result.data!), [1, 2, 3, 4]);
    });

    test('a file of another size than the message says is not this file', () async {
      source.claimedTotal = 99;

      final result = await repository.download(fileId: 'f_1', suggestedName: 'x.bin', expectedSize: 4);

      expect(result.exception, RepositoryException.internal);
      expect(source.abandoned, 1, reason: 'its bytes are let go unread');
      final destination = await cached('f_1', 'bin');
      expect(File('${destination.path}.part').existsSync(), isFalse);
    });

    test('a rejected pass is asked for again once; twice in a row is the server refusing', () async {
      source.getFailures.add(FileTransferFailure.passRejected);
      expect((await repository.download(fileId: 'f_1', suggestedName: 'x.bin')).data, isNotNull);

      source.getFailures.addAll([FileTransferFailure.passRejected, FileTransferFailure.passRejected]);
      expect((await repository.download(fileId: 'f_2', suggestedName: 'x.bin')).exception, RepositoryException.internal);
    });

    test('two callers asking for the same file share ONE transfer; the one who joins hears at once how far it is', () async {
      source.holdDownload = Completer<void>();
      final heardByPrefetch = <double>[];
      final heardByFileView = <double>[];

      final first = repository.download(fileId: 'f_same', suggestedName: 'photo.png', onProgress: heardByPrefetch.add);
      // Joined only once the first chunk is on disk and heard: under a loaded
      // run one turn of the event loop is not enough to get that far.
      for (var i = 0; i < 500 && !heardByPrefetch.contains(0.25); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final second = repository.download(fileId: 'f_same', suggestedName: 'photo.png', onProgress: heardByFileView.add);
      expect(heardByFileView, [0.25], reason: 'where the transfer stands, not silence until the next chunk');
      source.holdDownload!.complete();
      final results = await Future.wait([first, second]);

      expect(source.downloadBegins, 1);
      expect(results.map((r) => r.data).toSet(), hasLength(1));
      expect(await plainOf(results.first.data!), [1, 2, 3, 4], reason: 'the whole file, not a torn one');
      expect(heardByPrefetch.last, 1.0);
      expect(heardByFileView.last, 1.0);
    });

    test('a later download of the same file is a new transfer, not the finished one', () async {
      await repository.download(fileId: 'f_again', suggestedName: 'a.bin');
      await repository.clean();

      await repository.download(fileId: 'f_again', suggestedName: 'a.bin');

      expect(source.downloadBegins, 2);
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

    test('cancelTransfers ends what is moving', () async {
      await repository.cancelTransfers();

      expect(source.cancels, 1);
    });

    test('a change of path in the middle of the body is no failure: the rest comes at once, in the same call (FR-008)', () async {
      source
        ..bytesToReturn = big
        ..breakAfter = 100000
        ..breakWith = FileTransferFailure.pathChanged;

      final result = await repository.download(fileId: 'f_1', suggestedName: 'x.bin', expectedSize: big.length);

      expect(await plainOf(result.data!), big);
      expect(source.gets, [(0, null), (SealedFile.chunkSize, 'v1')], reason: 'only the rest from the last whole chunk, by the new path');
    });

    test('a change of path before the body is asked again at once', () async {
      source.getFailures.add(FileTransferFailure.pathChanged);

      final result = await repository.download(fileId: 'f_1', suggestedName: 'x.bin');

      expect(result.hasData, isTrue);
      expect(source.downloadBegins, 2);
    });

    test('a server answering with what the contract does not name is internal, counted towards giving up', () async {
      source.getFailures.add(FileTransferFailure.serverError);

      final result = await repository.download(fileId: 'f_1', suggestedName: 'x.bin');

      expect(result.exception, RepositoryException.internal);
    });

    test('a part the disk will not take lets the bytes go, and the attempt ends at once', () async {
      // Unreleased, the connection stayed open behind an attempt that had
      // already failed - and its transfer was never handed back.
      final destination = await cached('f_1', 'bin');
      Directory('${destination.path}.part').createSync(recursive: true);
      addTearDown(() => Directory('${destination.path}.part').existsSync() ? Directory('${destination.path}.part').deleteSync() : null);

      final result = await repository.download(fileId: 'f_1', suggestedName: 'x.bin').timeout(const Duration(seconds: 5));

      expect(result.hasData, isFalse);
      expect(source.abandoned, 1);
    });

    test('a download caught between two steps by a reset writes nothing after it', () async {
      // Asking for a pass has no transfer to end: without the check it went on
      // to write into a cache just emptied for somebody else.
      source.holdBegin = Completer<void>();
      final hold = source.holdBegin!;
      final running = repository.download(fileId: 'f_1', suggestedName: 'x.bin');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await repository.cancelTransfers();
      await repository.clean();
      hold.complete();
      final result = await running;

      expect(result.exception, RepositoryException.connection);
      final destination = await cached('f_1', 'bin');
      expect(destination.existsSync(), isFalse);
      expect(File('${destination.path}.part').existsSync(), isFalse);
      expect(source.gets, isEmpty, reason: 'the bytes were not even asked for');
    });

    test('clean removes the cache, half-downloaded files and their versions too (FR-017)', () async {
      await repository.download(fileId: 'f_1', suggestedName: 'x.bin');
      source.breakAfter = 1;
      await repository.download(fileId: 'f_2', suggestedName: 'y.bin');
      final half = await cached('f_2', 'bin');
      expect(File('${half.path}.part').existsSync(), isTrue);

      await repository.clean();

      expect(await repository.localPathFor(fileId: 'f_1', suggestedName: 'x.bin'), isNull);
      expect(File('${half.path}.part').existsSync(), isFalse);
      expect(File('${half.path}.part.tag').existsSync(), isFalse);
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
