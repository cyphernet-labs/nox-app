// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/data/entity/chat/wire/chat_wire_entity.dart';

part 'chats_wire_entity.freezed.dart';
part 'chats_wire_entity.g.dart';

/// Page wrapper for the chats list (network boundary — feature 018/S4). Mirrors
/// `ItemsEntity`: a page slice plus server offset metadata. JSON keys are an example
/// (TBD until the backend is chosen).
@freezed
abstract class ChatsWireEntity with _$ChatsWireEntity {
  const factory ChatsWireEntity({
    @Default(<ChatWireEntity>[]) List<ChatWireEntity> items,
    @JsonKey(name: 'page') required int page,
    @JsonKey(name: 'page_size') required int pageSize,
    @JsonKey(name: 'total') required int total,
  }) = _ChatsWireEntity;

  factory ChatsWireEntity.fromJson(Map<String, dynamic> json) => _$ChatsWireEntityFromJson(json);
}
