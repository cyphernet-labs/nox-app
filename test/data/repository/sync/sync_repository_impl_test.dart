import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SyncRepository repo;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase();
    repo = getIt<SyncRepository>();
  });

  tearDown(() async {
    await getIt.reset();
  });

  test('advanceCursor is monotonic: lower or equal values never move it back', () async {
    await repo.advanceCursor(100);
    await repo.advanceCursor(50); // stale replay duplicate
    await repo.advanceCursor(100); // exact duplicate
    expect(await repo.getCursor(), 100);

    await repo.advanceCursor(101);
    expect(await repo.getCursor(), 101);
  });

  test('clear resets the cursor to zero (the logout wipe)', () async {
    await repo.advanceCursor(9000);
    await repo.clear();
    expect(await repo.getCursor(), 0);
  });
}
