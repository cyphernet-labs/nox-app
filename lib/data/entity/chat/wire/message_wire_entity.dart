// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'message_wire_entity.freezed.dart';
part 'message_wire_entity.g.dart';

/// Wire DTO for a message attachment, 1:1 with contract v0 §5/§7:
/// `{file_id, name, size, mime, expires_at}`. BASIC TYPES ONLY (unix seconds
/// as int); coercion lives in `MessageWireMapper`. The file-type CATEGORY is
/// not on the wire — it is derived from the name's extension client-side
/// (contract §9.2). `localPath` never appears here (device-local).
@freezed
abstract class AttachmentWireEntity with _$AttachmentWireEntity {
  const factory AttachmentWireEntity({
    @JsonKey(name: 'file_id') required String fileId,
    required String name,
    required int size,
    required String mime,
    @JsonKey(name: 'expires_at') required int expiresAt, // unix seconds
  }) = _AttachmentWireEntity;

  factory AttachmentWireEntity.fromJson(Map<String, dynamic> json) => _$AttachmentWireEntityFromJson(json);
}

/// Wire DTO for the open-text message body object, contract v0 §5:
/// `{"type": "text", "text": "..."}`. Any non-text type is passed through
/// opaquely (the Q1 seam: the client must tolerate a future blob body).
@freezed
abstract class BodyWireEntity with _$BodyWireEntity {
  const factory BodyWireEntity({required String type, String? text}) = _BodyWireEntity;

  factory BodyWireEntity.fromJson(Map<String, dynamic> json) => _$BodyWireEntityFromJson(json);
}

/// Wire DTO for one message, 1:1 with contract v0 §5. Local-only concepts
/// (`status`, `isSystem`, `localPath`, unread state) DO NOT exist here —
/// they live in the domain/storage layers only. `clientMessageId` is present
/// only in the recipient's own messages (§5) and is dropped at mapping until
/// the persistent outbox phase (026) gives it a domain home. DISTINCT from
/// the local Sembast `MessageEntity`.
@freezed
abstract class MessageWireEntity with _$MessageWireEntity {
  const factory MessageWireEntity({
    @JsonKey(name: 'message_id') required String messageId,
    required int seq,
    @JsonKey(name: 'chat_id') required String chatId,
    @JsonKey(name: 'author_id') required String authorId,
    @JsonKey(name: 'author_label') required String authorLabel,
    @JsonKey(name: 'client_message_id') String? clientMessageId,
    @JsonKey(name: 'sent_at') required int sentAt, // unix seconds
    BodyWireEntity? body,
    AttachmentWireEntity? attachment,
  }) = _MessageWireEntity;

  factory MessageWireEntity.fromJson(Map<String, dynamic> json) => _$MessageWireEntityFromJson(json);
}
