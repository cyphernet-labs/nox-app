import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/chat/message_entity.dart';
import 'package:nox_app/data/mapper/base_mapper.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/general/app_clock.dart';

/// The single place where String<->enum, String<->DateTime and flat<->nested
/// attachment coercion for a message happens.
@lazySingleton
class MessageMapper extends BaseMapper<MessageEntity, MessageModel, dynamic, dynamic> {
  @override
  MessageModel toModel({required MessageEntity entity, dynamic Function(dynamic entity)? ad}) {
    return MessageModel(
      id: entity.id,
      chatId: entity.chatId,
      authorId: entity.authorId,
      authorLabel: entity.authorLabel,
      text: entity.text,
      sentAt: DateTime.tryParse(entity.sentAt)?.toUtc() ?? AppClock.now().toUtc(),
      status: MessageStatus.values.firstWhere((s) => s.name == entity.status, orElse: () => MessageStatus.none),
      isSystem: entity.isSystem,
      attachment: entity.attachmentId == null
          ? null
          : MessageAttachment(
              id: entity.attachmentId!,
              type: FileType.values.firstWhere((t) => t.name == entity.attachmentType, orElse: () => FileType.other),
              name: entity.attachmentName ?? '',
              sizeBytes: entity.attachmentSizeBytes ?? 0,
            ),
    );
  }

  @override
  MessageEntity toEntity({required MessageModel model, dynamic Function(dynamic entity)? ad}) {
    return MessageEntity(
      id: model.id,
      chatId: model.chatId,
      authorId: model.authorId,
      authorLabel: model.authorLabel,
      text: model.text,
      sentAt: model.sentAt.toUtc().toIso8601String(),
      status: model.status.name,
      isSystem: model.isSystem,
      attachmentId: model.attachment?.id,
      attachmentType: model.attachment?.type.name,
      attachmentName: model.attachment?.name,
      attachmentSizeBytes: model.attachment?.sizeBytes,
    );
  }
}
