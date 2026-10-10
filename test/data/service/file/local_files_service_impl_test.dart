import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/service/local_files_service.dart';
import 'package:nox_tor/vault.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/sealed_files.dart';

void main() {
  late LocalFilesService files;
  late Directory dir;
  final data = Uint8List.fromList(List<int>.generate(90000, (i) => (i * 5) & 0xFF));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    files = getIt<LocalFilesService>();
    dir = await Directory.systemTemp.createTemp('nox_local_files');
  });

  tearDown(() async {
    await files.clearCopies();
    await dir.delete(recursive: true);
    NoxVault.clear();
    await getIt.reset();
  });

  test('a sealed file is read into memory as its plain bytes (FR-006)', () async {
    final sealed = await writeSealed('${dir.path}/photo.png', data);

    expect(await files.read(sealed.path), data);
  });

  test("the person's own file is read as it is", () async {
    final plain = File('${dir.path}/picked.png')..writeAsBytesSync(data);

    expect(await files.read(plain.path), data);
  });

  test('Save writes the plain file where the person chose (FR-008)', () async {
    final sealed = await writeSealed('${dir.path}/report', data);
    final destination = '${dir.path}/Downloads-report.pdf';

    await files.saveTo(path: sealed.path, destination: destination);

    expect(File(destination).readAsBytesSync(), data);
  });

  test('a copy for a player is plain, and released it is gone (FR-007)', () async {
    final sealed = await writeSealed('${dir.path}/clip', data);

    final copy = await files.openCopy(path: sealed.path, name: 'clip.mp4');
    expect(File(copy).readAsBytesSync(), data);

    await files.releaseCopy(copy);
    expect(File(copy).existsSync(), isFalse);
  });

  test('every copy left goes at once', () async {
    final sealed = await writeSealed('${dir.path}/clip', data);
    final first = await files.openCopy(path: sealed.path, name: 'a.mp4');
    final second = await files.openCopy(path: sealed.path, name: 'b.pdf');

    await files.clearCopies();

    expect(File(first).existsSync(), isFalse);
    expect(File(second).existsSync(), isFalse);
  });
}
