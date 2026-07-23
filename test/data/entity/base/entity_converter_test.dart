import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/entity/base/entity_converter.dart';
import 'package:nox_app/data/entity/chat/wire/chat_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/chats_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/message_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/messages_wire_entity.dart';
import 'package:nox_app/data/entity/item/item_entity.dart';
import 'package:nox_app/data/entity/item/items_entity.dart';

/// A type NOT in the registry.
class _Unregistered {}

void main() {
  test('every registered wire entity resolves via fromJson (feature 018/S4)', () {
    const item = ItemEntity(id: 'i', name: 'n', status: 'active', createdAt: '2026-01-01T00:00:00.000Z', description: null);
    const items = ItemsEntity(items: [item], page: 1, pageSize: 20, total: 1);
    const chat = ChatWireEntity(id: 'c', name: 'n', lastMessagePreview: '', lastMessageAt: '2026-01-01T00:00:00.000Z', unreadCount: 0);
    const chats = ChatsWireEntity(items: [chat], page: 1, pageSize: 20, total: 1);
    const msg = MessageWireEntity(
      id: 'm',
      chatId: 'c',
      authorId: 'a',
      authorLabel: 'l',
      sentAt: '2026-01-01T00:00:00.000Z',
      status: 'none',
      isSystem: false,
    );
    const msgs = MessagesWireEntity(items: [msg], page: 1, pageSize: 20, total: 1);

    expect(const EntityConverter<ItemEntity>().fromJson(item.toJson()), item);
    expect(const EntityConverter<ItemsEntity>().fromJson(items.toJson()), items);
    expect(const EntityConverter<ChatWireEntity>().fromJson(chat.toJson()), chat);
    expect(const EntityConverter<ChatsWireEntity>().fromJson(chats.toJson()), chats);
    expect(const EntityConverter<MessageWireEntity>().fromJson(msg.toJson()), msg);
    expect(const EntityConverter<MessagesWireEntity>().fromJson(msgs.toJson()), msgs);
  });

  test('toJson is symmetric for each registered type', () {
    const chats = ChatsWireEntity(page: 1, pageSize: 20, total: 0);
    final json = const EntityConverter<ChatsWireEntity>().toJson(chats);
    expect(json, chats.toJson());
  });

  test('null passes through both directions', () {
    expect(const EntityConverter<ChatsWireEntity>().fromJson(null), isNull);
    expect(const EntityConverter<ChatsWireEntity>().toJson(null), isNull);
  });

  test('an unregistered type throws ArgumentError on both chains', () {
    expect(() => const EntityConverter<_Unregistered>().fromJson(<String, dynamic>{'x': 1}), throwsArgumentError);
    expect(() => const EntityConverter<_Unregistered>().toJson(_Unregistered()), throwsArgumentError);
  });
}
