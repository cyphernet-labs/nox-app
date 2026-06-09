// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/data/entity/item/item_entity.dart';

part 'items_entity.freezed.dart';
part 'items_entity.g.dart';

/// Page wrapper: a page slice plus server offset metadata. JSON key names are an
/// example — backend/protocol not chosen; replace with the real contract.
@freezed
abstract class ItemsEntity with _$ItemsEntity {
  const factory ItemsEntity({
    @Default(<ItemEntity>[]) List<ItemEntity> items,
    @JsonKey(name: 'page') required int page,
    @JsonKey(name: 'page_size') required int pageSize,
    @JsonKey(name: 'total') required int total,
  }) = _ItemsEntity;

  factory ItemsEntity.fromJson(Map<String, dynamic> json) => _$ItemsEntityFromJson(json);
}
