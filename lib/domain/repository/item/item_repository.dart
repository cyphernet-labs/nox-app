import 'package:nox_app/domain/model/item/item_model.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/item/get_items_config.dart';

/// Item verification-harness repository. The skeleton exposes the **network-only**
/// paginated list (the first-real-feature / chat-list pattern). Full CRUD + a
/// cache-first watch (with ItemDao + BehaviorSubject) is the blueprint's complete
/// Item example and arrives with a feature that needs caching.
abstract class ItemRepository {
  /// Paginated server-owned list (network-only). Returns the page slice paired
  /// with offset metadata (nextPage + total).
  Future<RepositoryResult<(List<ItemModel>, PageMetadata)>> getItems({required GetItemsConfig config});

  /// Resets cache/subjects (called on logout).
  Future<void> clean();
}
