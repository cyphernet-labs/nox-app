import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/item/item_entity.dart';
import 'package:nox_app/data/mapper/base_mapper.dart';
import 'package:nox_app/domain/model/item/item_model.dart';
import 'package:nox_app/domain/model/item/item_status.dart';

/// The single place where String<->enum and String<->DateTime coercion happens.
@lazySingleton
class ItemMapper extends BaseMapper<ItemEntity, ItemModel, dynamic, dynamic> {
  @override
  ItemModel toModel({required ItemEntity entity, dynamic Function(dynamic entity)? ad}) {
    return ItemModel(
      id: entity.id,
      name: entity.name,
      description: entity.description,
      status: ItemStatus.values.firstWhere((e) => e.name == entity.status, orElse: () => ItemStatus.draft),
      createdAt: DateTime.tryParse(entity.createdAt)?.toUtc() ?? DateTime.now().toUtc(),
    );
  }

  @override
  ItemEntity toEntity({required ItemModel model, dynamic Function(dynamic entity)? ad}) {
    return ItemEntity(
      id: model.id,
      name: model.name,
      description: model.description,
      status: model.status.name,
      createdAt: model.createdAt.toUtc().toIso8601String(),
    );
  }
}
