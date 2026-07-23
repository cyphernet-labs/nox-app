import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/repository/app_config/app_config_repository_impl.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // secure-storage mock channel

  AppConfigRepositoryImpl build({bool isTest = true}) => AppConfigRepositoryImpl(const FlutterSecureStorage(), isTest);

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('reading config before initialize throws a StateError', () {
    expect(() => build().config, throwsStateError);
  });

  test('exposes the stage flavor and a null (TBD) apiUrl after initializing', () async {
    final repo = build();
    await repo.initialize(flavorType: AppFlavorType.stage);
    expect(repo.config.flavor, AppFlavorType.stage);
    expect(repo.config.apiUrl, isNull); // TBD placeholder — no real requests this phase
  });

  test('exposes the prod flavor after initializing with prod', () async {
    final repo = build();
    await repo.initialize(flavorType: AppFlavorType.prod);
    expect(repo.config.flavor, AppFlavorType.prod);
  });

  test('re-initializing overwrites the previously configured flavor', () async {
    final repo = build();
    await repo.initialize(flavorType: AppFlavorType.stage);
    await repo.initialize(flavorType: AppFlavorType.prod);
    expect(repo.config.flavor, AppFlavorType.prod);
  });

  group('auth token + isTestEnvironment (S5)', () {
    test('getUserAuthIdToken returns null with empty secure storage (no token in the mock phase)', () async {
      FlutterSecureStorage.setMockInitialValues({});
      expect(await build().getUserAuthIdToken(), isNull);
    });

    test('getUserAuthIdToken returns the stored token when present (plumbing works end-to-end)', () async {
      FlutterSecureStorage.setMockInitialValues({'auth_id_token': 'tok-123'});
      expect(await build().getUserAuthIdToken(), 'tok-123');
    });

    test('an empty stored token is treated as absent (null)', () async {
      FlutterSecureStorage.setMockInitialValues({'auth_id_token': ''});
      expect(await build().getUserAuthIdToken(), isNull);
    });

    test('isTestEnvironment reflects the injected env-keyed flag', () {
      expect(build(isTest: true).isTestEnvironment, isTrue);
      expect(build(isTest: false).isTestEnvironment, isFalse);
    });
  });
}
