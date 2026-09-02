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
  final root = Directory('${Directory.systemTemp.path}/nox_test_paths')..createSync(recursive: true);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => root.path,
  );
}
