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

  test('concurrent advances resolve to the max (the check-then-write is transactional)', () async {
    // Unawaited interleaved advances: without the DAO-level transaction the
    // read-then-write pairs could interleave and persist a lower value last.
    await Future.wait([repo.advanceCursor(10), repo.advanceCursor(300), repo.advanceCursor(200), repo.advanceCursor(40)]);
    expect(await repo.getCursor(), 300);
  });

  test('clear resets the cursor to zero (the logout wipe)', () async {
    await repo.advanceCursor(9000);
    await repo.clear();
    expect(await repo.getCursor(), 0);
  });

  group('data-source epoch', () {
    test('the epoch survives a cursor advance, so the one-time wipe stays one-time', () async {
      await repo.setEpoch('live:http://127.0.0.1:8080');
      await repo.advanceCursor(42);

      // The cursor writers replace the whole state record; an epoch stored in
      // the same record would vanish here and re-trigger the wipe forever.
      expect(await repo.getEpoch(), 'live:http://127.0.0.1:8080');
      expect(await repo.getCursor(), 42);
    });

    test('the epoch survives the logout wipe, because a logout does not change which world the data came from', () async {
      await repo.setEpoch('live:http://127.0.0.1:8080');
      await repo.advanceCursor(9);
      await repo.clear();

      expect(await repo.getCursor(), 0);
      expect(await repo.getEpoch(), 'live:http://127.0.0.1:8080');
    });

    test('a fresh device has no epoch at all, which is what makes the first world change detectable', () async {
      expect(await repo.getEpoch(), isNull);
    });
  });
}
