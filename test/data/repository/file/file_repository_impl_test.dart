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
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A data source the test drives: it records what it was asked, and can refuse
/// the way the real server refuses.
class _FakeSource implements FileRemoteDataSource {
  int begins = 0;
  int puts = 0;
  FileTransferFailure? putFailure;
  String? beginErrorCode;
  String? downloadErrorCode;
  List<int> bytesToReturn = const [1, 2, 3, 4];
  bool truncateDownload = false;

  @override
  Future<ResponseEntity<UploadTicketWireEntity>> uploadBegin({required String name, required int sizeBytes, required String mime}) async {
    begins++;
    final code = beginErrorCode;
    if (code != null) {
      return ResponseEntity<UploadTicketWireEntity>(
        success: false,
        error: ErrorWireEntity(code: code, message: code),
      );
    }
    return ResponseEntity<UploadTicketWireEntity>(
      success: true,
      data: UploadTicketWireEntity(
        fileId: 'f_$begins',
        uploadUrl: '/files/pass_$begins',
        uploadToken: 'pass_$begins',
        maxAttachmentBytes: 104857600,
      ),
    );
  }

  @override
  Future<void> putBytes({required String uploadPath, required File file, TransferProgress? onProgress}) async {
    puts++;
    final failure = putFailure;
    // One-shot, like the real pass: the first attempt consumes the refusal.
    putFailure = null;
    if (failure != null) throw FileTransferException(failure);
    onProgress?.call(1, 1);
  }

  @override
  Future<ResponseEntity<DownloadTicketWireEntity>> downloadBegin({required String fileId}) async {
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
    destination.writeAsBytesSync(truncateDownload ? bytesToReturn.take(1).toList() : bytesToReturn);
    if (truncateDownload) throw const FileTransferException(FileTransferFailure.connection);
    onProgress?.call(bytesToReturn.length, bytesToReturn.length);
  }
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
    test('the id comes back only after the bytes are confirmed', () async {
      final result = await repository.upload(path: file.path, mime: 'application/octet-stream');

      expect(result.data, 'f_1');
      expect(source.begins, 1);
      expect(source.puts, 1);
    });

    test('a rejected pass is retried once with a NEW declaration, not with the dead one', () async {
      // The contract calls a burnt pass routine: ask for another. Reusing it
      // would fail identically forever.
      source.putFailure = FileTransferFailure.passRejected;

      final result = await repository.upload(path: file.path, mime: 'application/octet-stream');

      expect(result.data, 'f_2', reason: 'the second declaration issued a new id');
      expect(source.begins, 2, reason: 'a new pass was requested rather than the burnt one reused');
    });

    test('a size mismatch is terminal — announcing the same file again fails the same way', () async {
      source.putFailure = FileTransferFailure.sizeMismatch;

      final result = await repository.upload(path: file.path, mime: 'application/octet-stream');

      expect(result.exception, RepositoryException.invalidRequest);
      expect(source.begins, 1, reason: 'no point asking for another pass');
    });

    test('a file that is gone from disk fails before anything is declared', () async {
      file.deleteSync();

      final result = await repository.upload(path: file.path, mime: 'application/octet-stream');

      expect(result.exception, RepositoryException.notFound);
      expect(source.begins, 0, reason: 'nothing to declare');
    });

    test('a file over the limit is refused before a byte moves', () async {
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
