import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/item/items_entity.dart';
import 'package:nox_app/data/mapper/item/item_mapper.dart';
import 'package:nox_app/data/remote/api/item/get_items_api.dart';
import 'package:nox_app/data/repository/item/item_repository_impl.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/item/item_status.dart';
import 'package:nox_app/domain/repository/item/get_items_config.dart';
import 'package:nox_app/domain/repository/item/item_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'item_repository_impl_test.mocks.dart';

// GetItemsApi is the network-only mock source; mocked here only to force the
// error branches of BaseRepositoryHelper.execute.
@GenerateMocks([GetItemsApi])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Success + pagination path: the real (mock) GetItemsApi served through the
  // test-env DI — no mocks. It advertises total=47 with pageSize=20, i.e. three
  // pages: 20 + 20 + 7.
  group('ItemRepositoryImpl pagination over the DI-served mock source', () {
    late ItemRepository repository;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      await configureDependencies(Environment.test);
      repository = getIt<ItemRepository>();
    });

    tearDown(() async {
      await getIt.reset();
    });

    test('the first page maps 20 entities to models and advertises nextPage=2 over a total of 47', () async {
      final result = await repository.getItems(config: GetItemsConfig.firstPage());

      expect(result.hasData, isTrue);
      final (items, metadata) = result.data!;
      expect(items.length, GetItemsConfig.pageSize); // 20
      expect(metadata.total, 47);
      expect(metadata.nextPage, 2);
      // entity -> model coercion: String status -> ItemStatus enum.
      expect(items.first.id, 'item_0');
      expect(items.first.name, 'Item #0');
      expect(items.first.status, ItemStatus.active);
    });

    test('a middle page still carries a forward nextPage pointer', () async {
      final (items, metadata) = (await repository.getItems(config: GetItemsConfig.nextPage(page: 2))).data!;

      expect(items.length, GetItemsConfig.pageSize); // 20
      expect(metadata.total, 47);
      expect(metadata.nextPage, 3);
      expect(items.first.id, 'item_20');
    });

    test('the last page returns the 7-item tail with nextPage == null', () async {
      final (items, metadata) = (await repository.getItems(config: GetItemsConfig.nextPage(page: 3))).data!;

      expect(items.length, 7); // 47 - (2 * 20)
      expect(metadata.total, 47);
      expect(metadata.nextPage, isNull);
      expect(items.last.id, 'item_46');
    });
  });

  // Error mapping: the impl is constructed DIRECTLY with a mocked GetItemsApi.
  // The DI container is still booted because BaseRepositoryHelper.execute logs
  // via the logRepository global alias (getIt<LogRepository>()).
  group('ItemRepositoryImpl error mapping via BaseRepositoryHelper.execute', () {
    late MockGetItemsApi api;
    late ItemRepositoryImpl repository;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      await configureDependencies(Environment.test);
      api = MockGetItemsApi();
      repository = ItemRepositoryImpl(getIt<ItemMapper>(), api);
    });

    tearDown(() async {
      await getIt.reset();
    });

    test('a success envelope carrying a null payload collapses to RepositoryException.unknown', () async {
      when(api.execute(config: anyNamed('config'))).thenAnswer((_) async => const ResponseEntity<ItemsEntity>(success: true));

      final result = await repository.getItems(config: GetItemsConfig.firstPage());

      expect(result.hasData, isFalse);
      expect(result.exception, RepositoryException.unknown);
    });

    test('a DioException from the API maps to RepositoryException.internal', () async {
      when(api.execute(config: anyNamed('config'))).thenThrow(DioException(requestOptions: RequestOptions(path: 'v1/items')));

      final result = await repository.getItems(config: GetItemsConfig.firstPage());

      expect(result.hasData, isFalse);
      expect(result.exception, RepositoryException.internal);
    });

    test('any other exception from the API maps to RepositoryException.unknown', () async {
      when(api.execute(config: anyNamed('config'))).thenThrow(Exception('boom'));

      final result = await repository.getItems(config: GetItemsConfig.firstPage());

      expect(result.hasData, isFalse);
      expect(result.exception, RepositoryException.unknown);
    });
  });
}
