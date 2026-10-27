import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/data/entity/chat/wire/chat_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/chats_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/message_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/messages_wire_entity.dart';
import 'package:nox_app/data/entity/file/upload_ticket_wire_entity.dart';
import 'package:nox_app/data/entity/item/item_entity.dart';
import 'package:nox_app/data/entity/item/items_entity.dart';

bool _isType<E, T>() => <E>[] is List<T>;

/// Maintained-by-hand registry: resolves the generic `T` of `ResponseEntity<T>`
/// to a concrete entity fromJson/toJson. Every entity reachable via
/// `ResponseEntity<T>` MUST be registered in BOTH chains.
///
/// Populated (feature 018/S4) for every wire entity reachable via the envelope:
/// Item (reference) + chat + message list wrappers and their element entities. The
/// mocks build the envelope directly (never via `fromJson`), so this path is exercised
/// by the round-trip tests today and by a real backend's `ResponseEntity.fromJson` later.
/// An unregistered `T` still throws `ArgumentError` (explicit "no converter").
class EntityConverter<E> implements JsonConverter<E?, dynamic> {
  const EntityConverter();

  @override
  E? fromJson(dynamic json) {
    if (json == null) return null;
    if ((json is bool && _isType<E, bool>()) || _isType<E, bool?>()) {
      return json as E;
    }
    if (json is Map<String, dynamic>) {
      // Item (reference harness).
      if (_isType<E, ItemEntity>() || _isType<E, ItemEntity?>()) return ItemEntity.fromJson(json) as E;
      if (_isType<E, ItemsEntity>() || _isType<E, ItemsEntity?>()) return ItemsEntity.fromJson(json) as E;
      // Chat (feature 018/S4).
      if (_isType<E, ChatWireEntity>() || _isType<E, ChatWireEntity?>()) return ChatWireEntity.fromJson(json) as E;
      if (_isType<E, ChatsWireEntity>() || _isType<E, ChatsWireEntity?>()) return ChatsWireEntity.fromJson(json) as E;
      // Message (feature 018/S4).
      if (_isType<E, MessageWireEntity>() || _isType<E, MessageWireEntity?>()) return MessageWireEntity.fromJson(json) as E;
      if (_isType<E, MessagesWireEntity>() || _isType<E, MessagesWireEntity?>()) return MessagesWireEntity.fromJson(json) as E;
      // File chain (feature 028).
      if (_isType<E, UploadTicketWireEntity>() || _isType<E, UploadTicketWireEntity?>()) {
        return UploadTicketWireEntity.fromJson(json) as E;
      }
      if (_isType<E, DownloadTicketWireEntity>() || _isType<E, DownloadTicketWireEntity?>()) {
        return DownloadTicketWireEntity.fromJson(json) as E;
      }
    }
    throw ArgumentError('No converter found for type $E');
  }

  @override
  dynamic toJson(E? object) {
    if (object == null) return null;
    if (object is bool) return object;
    if (object is ItemEntity) return object.toJson();
    if (object is ItemsEntity) return object.toJson();
    if (object is ChatWireEntity) return object.toJson();
    if (object is ChatsWireEntity) return object.toJson();
    if (object is MessageWireEntity) return object.toJson();
    if (object is MessagesWireEntity) return object.toJson();
    if (object is UploadTicketWireEntity) return object.toJson();
    if (object is DownloadTicketWireEntity) return object.toJson();
    throw ArgumentError('No converter found for type $E');
  }
}
