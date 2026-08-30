import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/chat/chat_entity.dart';
import 'package:nox_app/data/mapper/base_mapper.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/general/app_clock.dart';

/// The single place where String<->DateTime coercion for a chat happens.
@lazySingleton
class ChatMapper extends BaseMapper<ChatEntity, ChatModel, dynamic, dynamic> {
  @override
  ChatModel toModel({required ChatEntity entity, dynamic Function(dynamic entity)? ad}) {
    return ChatModel(
      id: entity.id,
      name: entity.name,
      lastMessagePreview: entity.lastMessagePreview,
      // Stored as UTC ISO; hand the domain/UI local wall-clock (the chats list reads
      // lastMessageAt for relative time without a toLocal()).
      lastMessageAt: DateTime.tryParse(entity.lastMessageAt)?.toLocal() ?? AppClock.now(),
      unreadCount: entity.unreadCount,
      createdAt: entity.createdAt == null ? null : DateTime.fromMillisecondsSinceEpoch(entity.createdAt! * 1000, isUtc: true).toLocal(),
      createdByLabel: entity.createdByLabel,
    );
  }

  @override
  ChatEntity toEntity({required ChatModel model, dynamic Function(dynamic entity)? ad}) {
    return ChatEntity(
      id: model.id,
      name: model.name,
      lastMessagePreview: model.lastMessagePreview,
      lastMessageAt: model.lastMessageAt.toUtc().toIso8601String(),
      unreadCount: model.unreadCount,
      createdAt: model.createdAt == null ? null : model.createdAt!.toUtc().millisecondsSinceEpoch ~/ 1000,
      createdByLabel: model.createdByLabel,
    );
  }
}
