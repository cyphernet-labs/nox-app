import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/repository/app_config/app_config_repository_impl.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';

void main() {
  late AppConfigRepositoryImpl repository;

  setUp(() {
    repository = AppConfigRepositoryImpl();
  });

  test('reading config before initialize throws a StateError', () {
    expect(() => repository.config, throwsStateError);
  });

  test('exposes the stage flavor after initializing with stage', () async {
    await repository.initialize(flavorType: AppFlavorType.stage);
    expect(repository.config.flavor, AppFlavorType.stage);
  });

  test('exposes the prod flavor after initializing with prod', () async {
    await repository.initialize(flavorType: AppFlavorType.prod);
    expect(repository.config.flavor, AppFlavorType.prod);
  });

  test('re-initializing overwrites the previously configured flavor', () async {
    await repository.initialize(flavorType: AppFlavorType.stage);
    await repository.initialize(flavorType: AppFlavorType.prod);
    expect(repository.config.flavor, AppFlavorType.prod);
  });
}
