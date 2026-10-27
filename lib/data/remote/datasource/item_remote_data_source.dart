import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/item/items_entity.dart';
import 'package:nox_app/domain/repository/item/get_items_config.dart';

/// Network boundary for the verification-only Item harness. Keeps the wire-shaped
/// `ResponseEntity<ItemsEntity>` return (the DTO↔envelope reference path); populating
/// the converter for chat/message is S4, out of scope for feature 016.
abstract class ItemRemoteDataSource {
  Future<ResponseEntity<ItemsEntity>> getItems({required GetItemsConfig config});
}
