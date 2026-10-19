import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/exception/file_transfer_exception.dart';
import 'package:nox_app/data/remote/datasource/mock/mock_file_remote_data_source.dart';

/// The mock stands in for the server in tests and goldens, so it has to refuse
/// and continue the way the server does (contract §7, phase 043) - a mock that
/// says yes to everything keeps the suite green over the defects it exists to
/// catch.
void main() {
  late MockFileRemoteDataSource source;
  late File file;

  setUp(() {
    source = MockFileRemoteDataSource();
    file = File('${Directory.systemTemp.path}/nox_mock_${DateTime.now().microsecondsSinceEpoch}.bin')..writeAsBytesSync([1, 2, 3, 4]);
  });

  tearDown(() => file.existsSync() ? file.deleteSync() : null);

  test('a new upload starts from nothing', () async {
    final ticket = await source.uploadBegin(name: 'a.bin', sizeBytes: 4, mime: 'application/octet-stream');

    expect(ticket.data?.received, 0);
  });

  test('a known upload is continued under the same id, from what it holds', () async {
    final first = (await source.uploadBegin(name: 'a.bin', sizeBytes: 4, mime: 'application/octet-stream')).data!;
    await source.putBytes(uploadPath: first.uploadUrl, size: 4, offset: 0, body: file.openRead(0));

    final again = await source.uploadBegin(name: 'a.bin', sizeBytes: 4, mime: 'application/octet-stream', fileId: first.fileId);

    expect(again.data?.fileId, first.fileId);
    expect(again.data?.received, 4);
  });

  test('an upload it never had is not_found, and another size is invalid_request', () async {
    final unknown = await source.uploadBegin(name: 'a.bin', sizeBytes: 4, mime: 'application/octet-stream', fileId: 'f_gone');
    expect(unknown.error?.code, 'not_found');

    final first = (await source.uploadBegin(name: 'a.bin', sizeBytes: 4, mime: 'application/octet-stream')).data!;
    final other = await source.uploadBegin(name: 'a.bin', sizeBytes: 9, mime: 'application/octet-stream', fileId: first.fileId);
    expect(other.error?.code, 'invalid_request');
  });

  test('a spent pass is refused the way the server refuses it, not waved through', () async {
    // It used to return quietly, which told the repository the bytes were there.
    final ticket = (await source.uploadBegin(name: 'a.bin', sizeBytes: 4, mime: 'application/octet-stream')).data!;
    await source.putBytes(uploadPath: ticket.uploadUrl, size: 4, offset: 0, body: file.openRead(0));

    await expectLater(
      source.putBytes(uploadPath: ticket.uploadUrl, size: 4, offset: 0, body: file.openRead(0)),
      throwsA(isA<FileTransferException>().having((e) => e.failure, 'failure', FileTransferFailure.passRejected)),
    );
  });

  test('the rest comes for bytes of the version it holds, the whole file for anything else', () async {
    final ticket = (await source.uploadBegin(name: 'a.bin', sizeBytes: 4, mime: 'application/octet-stream')).data!;
    await source.putBytes(uploadPath: ticket.uploadUrl, size: 4, offset: 0, body: file.openRead(0));
    final pass = (await source.downloadBegin(fileId: ticket.fileId)).data!.downloadUrl;

    final first = await source.openBytes(downloadPath: pass, offset: 0);
    expect(first.whole, isTrue);
    expect([await for (final chunk in first.bytes) ...chunk], [1, 2, 3, 4]);

    final rest = await source.openBytes(downloadPath: pass, offset: 2, validator: first.validator);
    expect(rest.whole, isFalse);
    expect(rest.total, 4);
    expect([await for (final chunk in rest.bytes) ...chunk], [3, 4]);

    final other = await source.openBytes(downloadPath: pass, offset: 2, validator: 'another version');
    expect(other.whole, isTrue);
  });
}
