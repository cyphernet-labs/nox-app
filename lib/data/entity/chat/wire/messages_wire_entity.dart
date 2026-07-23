// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/data/entity/chat/wire/message_wire_entity.dart';

part 'messages_wire_entity.freezed.dart';
part 'messages_wire_entity.g.dart';

/// Page wrapper for a chat thread's messages (network boundary — feature 018/S4).
/// Mirrors `ItemsEntity`. JSON keys are an example (TBD until the backend is chosen).
@freezed
abstract class MessagesWireEntity with _$MessagesWireEntity {
  const factory MessagesWireEntity({
    @Default(<MessageWireEntity>[]) List<MessageWireEntity> items,
    @JsonKey(name: 'page') required int page,
    @JsonKey(name: 'page_size') required int pageSize,
    @JsonKey(name: 'total') required int total,
  }) = _MessagesWireEntity;

  factory MessagesWireEntity.fromJson(Map<String, dynamic> json) => _$MessagesWireEntityFromJson(json);
}
