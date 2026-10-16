import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/service/file/temp_copies.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_tor/vault.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/sealed_files.dart';

void main() {
  late TempCopies copies;
  late Directory root;
  late Directory sources;
  final data = Uint8List.fromList(List<int>.generate(150000, (i) => (i * 13) & 0xFF));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    copies = getIt<TempCopies>();
    root = Directory('${(await getTemporaryDirectory()).path}/${TempCopies.folder}');
    sources = await Directory.systemTemp.createTemp('nox_copies_src');
  });

  tearDown(() async {
    await copies.clear();
    await sources.delete(recursive: true);
    NoxVault.clear();
    await getIt.reset();
  });

  test('a sealed file comes out plain, under its own name, in a folder of its own', () async {
    final sealed = await writeSealed('${sources.path}/clip', data);

    final copy = await copies.make(source: sealed.path, name: 'holiday.mp4');

    expect(File(copy).readAsBytesSync(), data);
    expect(copy, endsWith('${Platform.pathSeparator}holiday.mp4'));
    expect(File(copy).parent.parent.path, root.path);
    if (!Platform.isWindows) {
      // Made like a temporary folder: on a desktop the temporary folder is
      // shared with every other user of it, and only this one may enter this.
      final mode = File(copy).parent.statSync().mode & 0x1FF;
      expect(mode, 0x1C0, reason: 'rwx------, not ${mode.toRadixString(8)}');
    }
  });

  test('the same file twice is two copies, and each goes on its own', () async {
    final sealed = await writeSealed('${sources.path}/clip', data);
    final first = await copies.make(source: sealed.path, name: 'a.mp4');
    final second = await copies.make(source: sealed.path, name: 'a.mp4');

    expect(first, isNot(second));
    await copies.release(first);

    expect(File(first).existsSync(), isFalse);
    expect(File(first).parent.existsSync(), isFalse, reason: 'the folder goes with the copy');
    expect(File(second).existsSync(), isTrue);
  });

  test('releasing is only ever of a copy: anything else is left alone', () async {
    final elsewhere = File('${sources.path}/mine.txt')..writeAsStringSync('the person\'s own');

    await copies.release(elsewhere.path);
    await copies.release(
      '${root.path}${Platform.pathSeparator}..${Platform.pathSeparator}${sources.path.split(Platform.pathSeparator).last}',
    );

    expect(elsewhere.existsSync(), isTrue);
  });

  test('a launch or a logout takes every copy left - the one another app may still be reading too', () async {
    final sealed = await writeSealed('${sources.path}/clip', data);
    final kept = await copies.make(source: sealed.path, name: 'report.pdf');

    await copies.clear();

    expect(File(kept).existsSync(), isFalse);
    expect(root.existsSync(), isFalse);
  });

  test('a copy that cannot be made in full leaves nothing behind', () async {
    final sealed = await writeSealed('${sources.path}/clip', data);
    final bytes = sealed.readAsBytesSync()..[40000] ^= 0x01;
    sealed.writeAsBytesSync(bytes);

    await expectLater(copies.make(source: sealed.path, name: 'clip.mp4'), throwsA(isA<VaultException>()));

    expect(root.listSync(), isEmpty);
  });

  test("the person's own file is copied as it is", () async {
    final plain = File('${sources.path}/photo.png')..writeAsBytesSync(data.sublist(0, 500));

    final copy = await copies.make(source: plain.path, name: 'photo.png');

    expect(File(copy).readAsBytesSync(), data.sublist(0, 500));
  });

  test('a name from another device stays a name: no separator or .. takes the copy out of its folder', () {
    expect(TempCopies.safeName('../../escape.mp4'), 'escape.mp4');
    expect(TempCopies.safeName(r'..\..\escape.mp4'), 'escape.mp4');
    expect(TempCopies.safeName('/etc/passwd'), 'passwd');
    expect(TempCopies.safeName('..'), 'file');
    expect(TempCopies.safeName(''), 'file');
    expect(TempCopies.safeName('a:b*c?.mp4'), 'a_b_c_.mp4');
    expect(TempCopies.safeName('holiday.mp4'), 'holiday.mp4');
  });
}
