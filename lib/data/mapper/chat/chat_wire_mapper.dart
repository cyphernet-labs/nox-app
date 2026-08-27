import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/chat/wire/chat_wire_entity.dart';
import 'package:nox_app/data/mapper/base_mapper.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';

/// Wire<->domain coercion for a chat, 1:1 with contract v0 §4. `toModel` =
/// wire->ChatModel (the repo, after unwrapping the envelope); `toEntity` =
/// ChatModel->wire (the mock generator). Coercion: unix seconds <-> local
/// DateTime. The unread counter is device-local (contract §8.3) and never
/// crosses this boundary: a chat arriving from the wire starts at 0 and the
/// local overlay owns it from there.
@lazySingleton
class ChatWireMapper extends BaseMapper<ChatWireEntity, ChatModel, dynamic, dynamic> {
  @override
  ChatModel toModel({required ChatWireEntity entity, dynamic Function(dynamic entity)? ad}) {
    return ChatModel(
      id: entity.chatId,
      name: entity.name,
      lastMessagePreview: entity.lastMessagePreview,
      lastMessageAt: DateTime.fromMillisecondsSinceEpoch(entity.lastActivityAt * 1000, isUtc: true).toLocal(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(entity.createdAt * 1000, isUtc: true).toLocal(),
      createdByLabel: entity.createdByLabel,
    );
  }

  @override
  ChatWireEntity toEntity({required ChatModel model, dynamic Function(dynamic entity)? ad}) {
    return ChatWireEntity(
      chatId: model.id,
      name: model.name,
      createdAt: (model.createdAt ?? model.lastMessageAt).toUtc().millisecondsSinceEpoch ~/ 1000,
      createdByLabel: model.createdByLabel ?? '',
      lastMessagePreview: model.lastMessagePreview,
      lastActivityAt: model.lastMessageAt.toUtc().millisecondsSinceEpoch ~/ 1000,
    );
  }
}
