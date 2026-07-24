// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'message_entity.freezed.dart';
part 'message_entity.g.dart';

/// DTO for a chat message (5.2) — @freezed + json_serializable, BASIC TYPES ONLY
/// (enum as String, DateTime as ISO-8601 String, attachment flattened to nullable
/// fields). All coercion lives in [MessageMapper].
@freezed
abstract class MessageEntity with _$MessageEntity {
  const factory MessageEntity({
    required String id,
    required String chatId,
    required String authorId,
    required String authorLabel,
    required String? text,
    required String sentAt, // ISO-8601
    required String status, // MessageStatus.name
    required bool isSystem,
    // Flattened attachment — all null when there is no attachment.
    required String? attachmentId,
    required String? attachmentType, // FileType.name
    required String? attachmentName,
    required int? attachmentSizeBytes,
    // Device-local file path (feature F4/F2). Optional (not `required`) so records
    // written before this field existed still read back (absent key → null).
    String? attachmentLocalPath,
  }) = _MessageEntity;

  factory MessageEntity.fromJson(Map<String, dynamic> json) => _$MessageEntityFromJson(json);
}
