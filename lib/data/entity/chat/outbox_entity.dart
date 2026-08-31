// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'outbox_entity.freezed.dart';
part 'outbox_entity.g.dart';

/// DTO for a queued send — @freezed + json_serializable, BASIC TYPES ONLY
/// (enum as String, DateTime as ISO-8601 String, attachment flattened to
/// nullable fields), mirroring [MessageEntity]. All coercion lives in
/// [OutboxMapper].
///
/// Every field added after the first ship MUST be optional (no `required`), so
/// a row written by an older build still decodes — the same rule that keeps
/// pre-025 message rows readable.
@freezed
abstract class OutboxEntity with _$OutboxEntity {
  const factory OutboxEntity({
    /// Duplicates the record key on purpose: a decoded entity has to be
    /// self-sufficient, and readers that never see the key still need the
    /// idempotency key it carries.
    required String clientMessageId,
    required String chatId,
    required int ordinal,
    required String createdAt, // ISO-8601
    required String status, // OutboxStatus.name
    required int attempts,

    /// Failures where the SERVER actually answered. Optional so rows
    /// written before this field existed still decode.
    @Default(0) int refusals,
    String? text,
    String? lastErrorCode,
    // Flattened attachment — all null when there is no attachment.
    String? attachmentId,
    String? attachmentType, // FileType.name
    String? attachmentName,
    int? attachmentSizeBytes,
    String? attachmentLocalPath,
    String? attachmentMime,
    int? attachmentExpiresAt, // unix seconds
  }) = _OutboxEntity;

  factory OutboxEntity.fromJson(Map<String, dynamic> json) => _$OutboxEntityFromJson(json);
}
