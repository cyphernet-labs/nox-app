// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_wire_entity.freezed.dart';
part 'chat_wire_entity.g.dart';

/// Wire DTO for one chat (network boundary — feature 018/S4). @freezed +
/// json_serializable, BASIC TYPES ONLY (DateTime as ISO-8601 String); all coercion
/// lives in `ChatWireMapper`. DISTINCT from the local Sembast `ChatEntity` (storage
/// shape). JSON keys are an example — backend/protocol not chosen (TBD).
@freezed
abstract class ChatWireEntity with _$ChatWireEntity {
  const factory ChatWireEntity({
    required String id,
    required String name,
    @JsonKey(name: 'last_message_preview') required String lastMessagePreview,
    @JsonKey(name: 'last_message_at') required String lastMessageAt, // DateTime as ISO-8601 String
    @JsonKey(name: 'unread_count') required int unreadCount,
  }) = _ChatWireEntity;

  factory ChatWireEntity.fromJson(Map<String, dynamic> json) => _$ChatWireEntityFromJson(json);
}
