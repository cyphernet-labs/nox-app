import 'dart:async';

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
  await testMain();
}
