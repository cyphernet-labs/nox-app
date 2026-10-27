import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global test bootstrap (auto-loaded by `flutter test`). Installs in-memory mock
/// backends for the platform storage plugins so any test that builds the DI graph
/// (`configureDependencies` → `getIt.allReady()`, which `@preResolve`s
/// SharedPreferences and lazily provides FlutterSecureStorage) resolves without a
/// real platform channel. Individual tests may re-seed via `setMockInitialValues`.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
  _mockPathProvider();
  await testMain();
}

/// Answers the directory questions `path_provider` would put on a platform
/// channel that does not exist under `flutter test`.
///
/// The attachment cache (feature 028) asks for one on every download, and an
/// unanswered channel throws — which surfaces as a screen stuck on its progress
/// bar rather than as a plugin error, so it is worth handling once here instead
/// of in each test that happens to touch a file.
void _mockPathProvider() {
  // A FRESH directory per run, not one shared forever: a file cached by one
  // test would otherwise satisfy the next one's cache check and hide exactly
  // the failure that test exists to catch.
  // A fresh directory per test PROCESS. `flutter test` runs each file in its
  // own isolate, so this is per-file isolation — enough that a file cached by
  // one suite cannot satisfy another's cache check and hide the failure that
  // check exists to catch. It is not cleaned up here: this hook runs outside
  // any test, so there is nothing to hang a teardown on, and the OS reclaims a
  // temp directory anyway.
  final root = Directory.systemTemp.createTempSync('nox_test_paths');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => root.path,
  );
}
