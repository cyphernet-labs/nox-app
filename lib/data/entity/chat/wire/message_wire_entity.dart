// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'message_wire_entity.freezed.dart';
part 'message_wire_entity.g.dart';

/// Wire DTO for a message attachment (nested in [MessageWireEntity]). BASIC TYPES
/// ONLY (FileType as String); coercion in `MessageWireMapper`.
@freezed
abstract class MessageAttachmentWireEntity with _$MessageAttachmentWireEntity {
  const factory MessageAttachmentWireEntity({
    required String id,
    required String type, // FileType encoded as String
    required String name,
    @JsonKey(name: 'size_bytes') required int sizeBytes,
  }) = _MessageAttachmentWireEntity;

  factory MessageAttachmentWireEntity.fromJson(Map<String, dynamic> json) => _$MessageAttachmentWireEntityFromJson(json);
}

/// Wire DTO for one message (network boundary — feature 018/S4). @freezed +
/// json_serializable, BASIC TYPES ONLY (enum as String, DateTime as ISO-8601 String,
/// nested attachment object). DISTINCT from the local Sembast `MessageEntity`.
@freezed
abstract class MessageWireEntity with _$MessageWireEntity {
  const factory MessageWireEntity({
    required String id,
    @JsonKey(name: 'chat_id') required String chatId,
    @JsonKey(name: 'author_id') required String authorId,
    @JsonKey(name: 'author_label') required String authorLabel,
    String? text,
    @JsonKey(name: 'sent_at') required String sentAt, // DateTime as ISO-8601 String
    required String status, // MessageStatus encoded as String
    @JsonKey(name: 'is_system') required bool isSystem,
    MessageAttachmentWireEntity? attachment,
  }) = _MessageWireEntity;

  factory MessageWireEntity.fromJson(Map<String, dynamic> json) => _$MessageWireEntityFromJson(json);
}
