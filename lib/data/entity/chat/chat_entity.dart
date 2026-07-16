// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_entity.freezed.dart';
part 'chat_entity.g.dart';

/// DTO for a chat (5.1) — @freezed + json_serializable, BASIC TYPES ONLY
/// (DateTime encoded as ISO-8601 String, sortable lexicographically). All coercion
/// lives in [ChatMapper].
@freezed
abstract class ChatEntity with _$ChatEntity {
  const factory ChatEntity({
    required String id,
    required String name,
    required String lastMessagePreview,
    required String lastMessageAt, // DateTime encoded as ISO-8601 String
    required int unreadCount,
  }) = _ChatEntity;

  factory ChatEntity.fromJson(Map<String, dynamic> json) => _$ChatEntityFromJson(json);
}
