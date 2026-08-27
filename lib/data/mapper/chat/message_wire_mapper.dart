import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/chat/wire/message_wire_entity.dart';
import 'package:nox_app/data/mapper/base_mapper.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/general/app_clock.dart';

/// Wire<->domain coercion for a message, 1:1 with contract v0 §5. `toModel` =
/// wire->MessageModel (the repo); `toEntity` = MessageModel->wire (the mock
/// generator). Coercions: unix seconds <-> DateTime; `body {type:"text"}` <->
/// flat text (a non-text body maps to a null text — the Q1 seam); the file
/// CATEGORY is derived from the name's extension (contract §9.2), never
/// carried on the wire. Local-only fields (`status`, `isSystem`, `localPath`)
/// do not cross this boundary; `clientMessageId` is parsed but dropped until
/// the persistent outbox (phase 026) gives it a domain home.
@lazySingleton
class MessageWireMapper extends BaseMapper<MessageWireEntity, MessageModel, dynamic, dynamic> {
  static const String _textBodyType = 'text';

  @override
  MessageModel toModel({required MessageWireEntity entity, dynamic Function(dynamic entity)? ad}) {
    final attachment = entity.attachment;
    final body = entity.body;
    return MessageModel(
      id: entity.messageId,
      seq: entity.seq,
      chatId: entity.chatId,
      authorId: entity.authorId,
      authorLabel: entity.authorLabel,
      text: body != null && body.type == _textBodyType ? body.text : null,
      sentAt: DateTime.fromMillisecondsSinceEpoch(entity.sentAt * 1000, isUtc: true).toLocal(),
      attachment: attachment == null
          ? null
          : MessageAttachment(
              id: attachment.fileId,
              type: FileType.fromExtension(_extensionOf(attachment.name)),
              name: attachment.name,
              sizeBytes: attachment.size,
              mime: attachment.mime,
              expiresAt: DateTime.fromMillisecondsSinceEpoch(attachment.expiresAt * 1000, isUtc: true).toLocal(),
            ),
    );
  }

  @override
  MessageWireEntity toEntity({required MessageModel model, dynamic Function(dynamic entity)? ad}) {
    final attachment = model.attachment;
    final text = model.text;
    return MessageWireEntity(
      messageId: model.id,
      seq: model.seq,
      chatId: model.chatId,
      authorId: model.authorId,
      authorLabel: model.authorLabel,
      sentAt: model.sentAt.toUtc().millisecondsSinceEpoch ~/ 1000,
      body: text == null ? null : BodyWireEntity(type: _textBodyType, text: text),
      attachment: attachment == null
          ? null
          : AttachmentWireEntity(
              fileId: attachment.id,
              name: attachment.name,
              size: attachment.sizeBytes,
              // Drafts picked locally have no wire metadata yet; the mock
              // echo needs concrete values, mirroring what a real server
              // assembles from uploadBegin.
              mime: attachment.mime ?? 'application/octet-stream',
              expiresAt: (attachment.expiresAt ?? AppClock.now().add(const Duration(days: 3650))).toUtc().millisecondsSinceEpoch ~/ 1000,
            ),
    );
  }

  static String? _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return null;
    return name.substring(dot + 1);
  }
}
