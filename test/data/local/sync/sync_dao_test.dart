import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/local/sync/sync_dao.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SyncDao dao;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase();
    dao = getIt<SyncDao>();
  });

  tearDown(() async {
    await getIt.reset();
  });

  test('an empty store reads as cursor 0', () async {
    expect(await dao.readSince(), 0);
  });

  test('the written cursor persists across DAO instances over the same database', () async {
    await dao.writeSince(1042);
    // A fresh DAO over the same (in-memory, isolate-lived) database sees the
    // value - the restart-persistence shape without process machinery.
    final second = SyncDao(getIt<AppDatabase>());
    expect(await second.readSince(), 1042);
  });

  test('cleanData drops the cursor back to 0', () async {
    await dao.writeSince(7);
    await dao.cleanData();
    expect(await dao.readSince(), 0);
  });
}
