import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/picker_copies.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory root;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    root = Directory.systemTemp.createTempSync('picker_copies');
    PickerCopies.debugCache = '${root.path}/cache';
    PickerCopies.debugTemp = '${root.path}/tmp';
  });

  tearDown(() async {
    PickerCopies.debugAndroid = null;
    PickerCopies.debugIos = null;
    PickerCopies.debugCache = null;
    PickerCopies.debugTemp = null;
    root.deleteSync(recursive: true);
    await getIt.reset();
  });

  File make(String path) => File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync('plain bytes of a picked file');

  test("on Android the picker's copy in a uuid folder of the cache goes, folder and all", () async {
    PickerCopies.debugAndroid = true;
    final copy = make('${root.path}/cache/0b0c4a6e-3d1f-3a5b-9c1e-1f2e3d4c5b6a/scan.pdf');
    final ours = make('${root.path}/cache/nox_tor_cache/state');

    await PickerCopies.release(copy.path);

    expect(copy.existsSync(), isFalse);
    expect(copy.parent.existsSync(), isFalse);
    expect(ours.existsSync(), isTrue, reason: 'only the picker\'s folders are its');
  });

  test("on iOS the picker's import in the tmp inbox goes", () async {
    PickerCopies.debugAndroid = false;
    PickerCopies.debugIos = true;
    final copy = make('${root.path}/tmp/com.cyphernetlabs.noxapp-Inbox/scan.pdf');

    await PickerCopies.release(copy.path);

    expect(copy.existsSync(), isFalse);
  });

  test("a file of the person's own is never touched - elsewhere on a phone, or anywhere on a desktop", () async {
    final own = make('${root.path}/Documents/scan.pdf');
    final nested = make('${root.path}/cache/0b0c4a6e-3d1f-3a5b-9c1e-1f2e3d4c5b6a/deeper/scan.pdf');

    PickerCopies.debugAndroid = true;
    await PickerCopies.release(own.path);
    await PickerCopies.release(nested.path);
    PickerCopies.debugAndroid = false;
    PickerCopies.debugIos = false;
    final looksLikeOne = make('${root.path}/cache/0b0c4a6e-3d1f-3a5b-9c1e-1f2e3d4c5b6a/scan.pdf');
    await PickerCopies.release(looksLikeOne.path);

    expect(own.existsSync(), isTrue);
    expect(nested.existsSync(), isTrue);
    expect(looksLikeOne.existsSync(), isTrue, reason: 'a desktop path is the person\'s own file');
  });

  test("a logout takes every copy the picker left, and nothing else", () async {
    PickerCopies.debugAndroid = true;
    final first = make('${root.path}/cache/0b0c4a6e-3d1f-3a5b-9c1e-1f2e3d4c5b6a/a.pdf');
    final second = make('${root.path}/cache/1c1d5b7f-4e2a-4b6c-8d2f-2a3b4c5d6e7f/b.jpg');
    final ours = make('${root.path}/cache/nox_tor_cache/state');

    await PickerCopies.clear();

    expect(first.existsSync(), isFalse);
    expect(second.existsSync(), isFalse);
    expect(ours.existsSync(), isTrue);
  });
}
