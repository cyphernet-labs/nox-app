import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/chat/wire/chat_wire_entity.dart';
import 'package:nox_app/data/mapper/base_mapper.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/general/app_clock.dart';

/// Wire<->domain coercion for a chat (feature 018/S4). `toModel` = wire->ChatModel
/// (the repo, after unwrapping the envelope); `toEntity` = ChatModel->wire (the mock
/// generator). Bidirectional and loss-free — the same String<->DateTime convention as
/// `ChatMapper` (UTC ISO on the wire, local wall-clock in the model).
@lazySingleton
class ChatWireMapper extends BaseMapper<ChatWireEntity, ChatModel, dynamic, dynamic> {
  @override
  ChatModel toModel({required ChatWireEntity entity, dynamic Function(dynamic entity)? ad}) {
    return ChatModel(
      id: entity.id,
      name: entity.name,
      lastMessagePreview: entity.lastMessagePreview,
      lastMessageAt: DateTime.tryParse(entity.lastMessageAt)?.toLocal() ?? AppClock.now(),
      unreadCount: entity.unreadCount,
    );
  }

  @override
  ChatWireEntity toEntity({required ChatModel model, dynamic Function(dynamic entity)? ad}) {
    return ChatWireEntity(
      id: model.id,
      name: model.name,
      lastMessagePreview: model.lastMessagePreview,
      lastMessageAt: model.lastMessageAt.toUtc().toIso8601String(),
      unreadCount: model.unreadCount,
    );
  }
}
