import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/chat/outbox_entity.dart';
import 'package:nox_app/data/mapper/base_mapper.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/outbox_entry.dart';
import 'package:nox_app/domain/model/chat/outbox_status.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/general/app_clock.dart';

/// The single place where String<->enum, String<->DateTime and flat<->nested
/// attachment coercion for a queued send happens. Mirrors [MessageMapper] field
/// for field: the queue holds the same payload a message does, minus everything
/// the server owns (id, seq, timestamps of record).
@lazySingleton
class OutboxMapper extends BaseMapper<OutboxEntity, OutboxEntry, dynamic, dynamic> {
  @override
  OutboxEntry toModel({required OutboxEntity entity, dynamic Function(dynamic entity)? ad}) {
    return OutboxEntry(
      clientMessageId: entity.clientMessageId,
      chatId: entity.chatId,
      ordinal: entity.ordinal,
      // Stored as UTC ISO; hand the domain local wall-clock, like MessageMapper —
      // the queued bubble renders its time through the same formatter.
      createdAt: DateTime.tryParse(entity.createdAt)?.toLocal() ?? AppClock.now(),
      status: OutboxStatus.values.firstWhere((s) => s.name == entity.status, orElse: () => OutboxStatus.pending),
      attempts: entity.attempts,
      text: entity.text,
      lastErrorCode: entity.lastErrorCode,
      attachment: entity.attachmentId == null
          ? null
          : MessageAttachment(
              id: entity.attachmentId!,
              type: FileType.values.firstWhere((t) => t.name == entity.attachmentType, orElse: () => FileType.other),
              name: entity.attachmentName ?? '',
              sizeBytes: entity.attachmentSizeBytes ?? 0,
              mime: entity.attachmentMime,
              expiresAt: entity.attachmentExpiresAt == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(entity.attachmentExpiresAt! * 1000, isUtc: true).toLocal(),
              localPath: entity.attachmentLocalPath,
            ),
    );
  }

  @override
  OutboxEntity toEntity({required OutboxEntry model, dynamic Function(dynamic entity)? ad}) {
    return OutboxEntity(
      clientMessageId: model.clientMessageId,
      chatId: model.chatId,
      ordinal: model.ordinal,
      createdAt: model.createdAt.toUtc().toIso8601String(),
      status: model.status.name,
      attempts: model.attempts,
      text: model.text,
      lastErrorCode: model.lastErrorCode,
      attachmentId: model.attachment?.id,
      attachmentType: model.attachment?.type.name,
      attachmentName: model.attachment?.name,
      attachmentSizeBytes: model.attachment?.sizeBytes,
      attachmentLocalPath: model.attachment?.localPath,
      attachmentMime: model.attachment?.mime,
      attachmentExpiresAt: model.attachment?.expiresAt == null ? null : model.attachment!.expiresAt!.toUtc().millisecondsSinceEpoch ~/ 1000,
    );
  }
}
