import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/model/item/item_status.dart';

part 'item_model.freezed.dart';

/// Domain model — @freezed, no JSON (.freezed.dart only). Derived/business logic
/// lives in extension getters, never in the @freezed body.
@freezed
abstract class ItemModel with _$ItemModel {
  const factory ItemModel({
    required String id,
    required String name,
    required String? description,
    required ItemStatus status,
    required DateTime createdAt,
  }) = _ItemModel;
}

extension ItemModelExt on ItemModel {
  bool get isArchived => status == ItemStatus.archived;

  String get displayName => name.trim().isEmpty ? 'Untitled' : name;
}
