// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/data/entity/chat/wire/message_wire_entity.dart';

part 'messages_wire_entity.freezed.dart';
part 'messages_wire_entity.g.dart';

/// Page wrapper for a chat's history, 1:1 with contract v0 §5:
/// `{messages: [...], has_more}` — a backward-paged slice requested by
/// `before_seq`, ascending by seq inside the batch. No page numbers, no
/// total (they do not exist for messages on the wire).
@freezed
abstract class MessagesWireEntity with _$MessagesWireEntity {
  const factory MessagesWireEntity({
    @Default(<MessageWireEntity>[]) List<MessageWireEntity> messages,
    @JsonKey(name: 'has_more') required bool hasMore,
  }) = _MessagesWireEntity;

  factory MessagesWireEntity.fromJson(Map<String, dynamic> json) => _$MessagesWireEntityFromJson(json);
}
