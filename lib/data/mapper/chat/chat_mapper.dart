import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/chat/chat_entity.dart';
import 'package:nox_app/data/mapper/base_mapper.dart';
import 'package:nox_app/domain/model/chat/chat_creation.dart';
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
      creation: creationFrom(entity.creation),
    );
  }

  /// The stored value of [creation] (phase 041). Kept apart from the enum's
  /// names on purpose: the records outlive a rename of the Dart identifiers.
  static String? creationValue(ChatCreation? creation) => switch (creation) {
    null => null,
    ChatCreation.pending => 'pending',
    ChatCreation.nameTaken => 'name_taken',
    ChatCreation.failed => 'failed',
  };

  /// Anything unrecognised reads as `pending`: a chat the server may not have
  /// must never pass for one it has - its messages would go to an id nobody
  /// knows.
  static ChatCreation? creationFrom(String? value) => switch (value) {
    null => null,
    'name_taken' => ChatCreation.nameTaken,
    'failed' => ChatCreation.failed,
    _ => ChatCreation.pending,
  };

  /// [lastOpenedSeq] is device-local and has no domain counterpart: it never
  /// crosses the wire and the UI never sees it, so it cannot be recovered from
  /// the model. Callers merging a wire row into a stored one must hand the
  /// stored value back, or the mark is lost and the chat looks never-opened -
  /// which silently hides its badge.
  ///
  /// It cannot be `required`: this overrides a base-class method, and a
  /// subtype may not demand more than its supertype. The entity field IS
  /// required, so a new construction site is a compile error - but a caller of
  /// THIS method that forgets is not. `chat_mapper_test` pins the round trip
  /// for that reason.
  @override
  ChatEntity toEntity({required ChatModel model, dynamic Function(dynamic entity)? ad, int? lastOpenedSeq}) {
    return ChatEntity(
      id: model.id,
      name: model.name,
      lastMessagePreview: model.lastMessagePreview,
      lastMessageAt: model.lastMessageAt.toUtc().toIso8601String(),
      unreadCount: model.unreadCount,
      lastOpenedSeq: lastOpenedSeq,
      createdAt: model.createdAt == null ? null : model.createdAt!.toUtc().millisecondsSinceEpoch ~/ 1000,
      createdByLabel: model.createdByLabel,
      creation: creationValue(model.creation),
    );
  }
}
