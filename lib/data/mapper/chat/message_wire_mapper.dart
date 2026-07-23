import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/chat/wire/message_wire_entity.dart';
import 'package:nox_app/data/mapper/base_mapper.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/general/app_clock.dart';

/// Wire<->domain coercion for a message (feature 018/S4), including the nested
/// attachment. `toModel` = wire->MessageModel (the repo); `toEntity` = MessageModel->wire
/// (the mock generator). Mirrors `MessageMapper`: enum<->String (name), DateTime<->ISO,
/// null-safe attachment. Bidirectional and loss-free.
@lazySingleton
class MessageWireMapper extends BaseMapper<MessageWireEntity, MessageModel, dynamic, dynamic> {
  @override
  MessageModel toModel({required MessageWireEntity entity, dynamic Function(dynamic entity)? ad}) {
    final attachment = entity.attachment;
    return MessageModel(
      id: entity.id,
      chatId: entity.chatId,
      authorId: entity.authorId,
      authorLabel: entity.authorLabel,
      text: entity.text,
      sentAt: DateTime.tryParse(entity.sentAt)?.toLocal() ?? AppClock.now(),
      status: MessageStatus.values.firstWhere((s) => s.name == entity.status, orElse: () => MessageStatus.none),
      isSystem: entity.isSystem,
      attachment: attachment == null
          ? null
          : MessageAttachment(
              id: attachment.id,
              type: FileType.values.firstWhere((t) => t.name == attachment.type, orElse: () => FileType.other),
              name: attachment.name,
              sizeBytes: attachment.sizeBytes,
            ),
    );
  }

  @override
  MessageWireEntity toEntity({required MessageModel model, dynamic Function(dynamic entity)? ad}) {
    final attachment = model.attachment;
    return MessageWireEntity(
      id: model.id,
      chatId: model.chatId,
      authorId: model.authorId,
      authorLabel: model.authorLabel,
      text: model.text,
      sentAt: model.sentAt.toUtc().toIso8601String(),
      status: model.status.name,
      isSystem: model.isSystem,
      attachment: attachment == null
          ? null
          : MessageAttachmentWireEntity(
              id: attachment.id,
              type: attachment.type.name,
              name: attachment.name,
              sizeBytes: attachment.sizeBytes,
            ),
    );
  }
}
