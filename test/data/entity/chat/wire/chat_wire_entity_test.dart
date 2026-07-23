import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/chat/wire/chat_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/chats_wire_entity.dart';

void main() {
  const chat = ChatWireEntity(
    id: 'chat_0',
    name: 'Design crit',
    lastMessagePreview: 'hi',
    lastMessageAt: '2026-06-15T21:30:00.000Z',
    unreadCount: 3,
  );
  const page = ChatsWireEntity(items: [chat], page: 1, pageSize: 20, total: 1);

  test('ChatWireEntity JSON round-trips (fromJson∘toJson)', () {
    expect(ChatWireEntity.fromJson(chat.toJson()), chat);
    // snake_case keys are the wire contract.
    expect(chat.toJson()['last_message_at'], '2026-06-15T21:30:00.000Z');
    expect(chat.toJson()['unread_count'], 3);
  });

  test('ChatsWireEntity JSON round-trips with its nested items', () {
    expect(ChatsWireEntity.fromJson(page.toJson()), page);
    expect(page.toJson()['page_size'], 20);
  });

  test('ResponseEntity<ChatsWireEntity>.fromJson resolves data via the registry (not throwing)', () {
    final envelope = ResponseEntity<ChatsWireEntity>(success: true, data: page);
    final json = envelope.toJson();
    final parsed = ResponseEntity<ChatsWireEntity>.fromJson(json);
    expect(parsed.success, isTrue);
    expect(parsed.data, page);
  });
}
