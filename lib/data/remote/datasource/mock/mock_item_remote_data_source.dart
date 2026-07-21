import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/item/items_entity.dart';
import 'package:nox_app/data/remote/api/item/get_items_api.dart';
import 'package:nox_app/data/remote/datasource/item_remote_data_source.dart';
import 'package:nox_app/domain/repository/item/get_items_config.dart';

/// Mock [ItemRemoteDataSource] — delegates to the [GetItemsApi] generator (the
/// wire-shaped `ResponseEntity<ItemsEntity>` reference path). Bound for all boot
/// environments; flip to real per `contracts/di-binding.md`.
@LazySingleton(as: ItemRemoteDataSource, env: [Environment.dev, Environment.prod, Environment.test])
class MockItemRemoteDataSource implements ItemRemoteDataSource {
  MockItemRemoteDataSource(this._api);

  final GetItemsApi _api;

  @override
  Future<ResponseEntity<ItemsEntity>> getItems({required GetItemsConfig config}) => _api.execute(config: config);
}
