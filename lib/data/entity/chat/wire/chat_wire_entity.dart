// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_wire_entity.freezed.dart';
part 'chat_wire_entity.g.dart';

/// Wire DTO for one chat, 1:1 with contract v0 §4: `{chat_id, name,
/// created_at, created_by_label, last_message_preview, last_activity_at}`.
/// BASIC TYPES ONLY (unix seconds as int); coercion lives in
/// `ChatWireMapper`. `unread_count` deliberately DOES NOT exist on the wire —
/// the unread counter is device-local (contract §8.3). DISTINCT from the
/// local Sembast `ChatEntity` (storage shape).
@freezed
abstract class ChatWireEntity with _$ChatWireEntity {
  const factory ChatWireEntity({
    @JsonKey(name: 'chat_id') required String chatId,
    required String name,
    @JsonKey(name: 'created_at') required int createdAt, // unix seconds
    @JsonKey(name: 'created_by_label') required String createdByLabel,
    @JsonKey(name: 'last_message_preview') required String lastMessagePreview,
    @JsonKey(name: 'last_activity_at') required int lastActivityAt, // unix seconds
  }) = _ChatWireEntity;

  factory ChatWireEntity.fromJson(Map<String, dynamic> json) => _$ChatWireEntityFromJson(json);
}
