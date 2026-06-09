import 'package:injectable/injectable.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/data/mapper/item/item_mapper.dart';
import 'package:nox_app/data/remote/api/item/get_items_api.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/item/item_model.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/item/get_items_config.dart';
import 'package:nox_app/domain/repository/item/item_repository.dart';

/// Network-only paginated list (no DAO/subject — carve-out). Skeleton source is
/// a mock (FR-013). Wraps every call in BaseRepositoryHelper.execute (logs via
/// LogRepository, maps errors to RepositoryException).
@LazySingleton(as: ItemRepository, env: [Environment.dev, Environment.prod, Environment.test])
class ItemRepositoryImpl with BaseRepositoryHelper implements ItemRepository {
  ItemRepositoryImpl(this._itemMapper, this._getItemsApi);

  final ItemMapper _itemMapper;
  final GetItemsApi _getItemsApi;

  @override
  Future<RepositoryResult<(List<ItemModel>, PageMetadata)>> getItems({required GetItemsConfig config}) {
    return execute<(List<ItemModel>, PageMetadata)>(() async {
      final response = await _getItemsApi.execute(config: config);
      final entity = response.data;
      if (entity == null) {
        return RepositoryResult<(List<ItemModel>, PageMetadata)>.error(exception: RepositoryException.unknown);
      }
      final models = _itemMapper.toListModel(entities: entity.items);
      final hasMore = (entity.page * entity.pageSize) < entity.total;
      final metadata = PageMetadata(total: entity.total, nextPage: hasMore ? entity.page + 1 : null);
      return RepositoryResult<(List<ItemModel>, PageMetadata)>.success(data: (models, metadata));
    });
  }

  @override
  Future<void> clean() async {}
}
