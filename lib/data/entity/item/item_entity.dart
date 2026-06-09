// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'item_entity.freezed.dart';
part 'item_entity.g.dart';

/// DTO — @freezed + json_serializable, BASIC TYPES ONLY (enum as String,
/// DateTime as ISO-8601 String). All coercion lives in the mapper.
@freezed
abstract class ItemEntity with _$ItemEntity {
  const factory ItemEntity({
    required String id,
    required String name,
    required String status, // enum encoded as String
    required String createdAt, // DateTime encoded as ISO-8601 String
    required String? description,
  }) = _ItemEntity;

  factory ItemEntity.fromJson(Map<String, dynamic> json) => _$ItemEntityFromJson(json);
}
