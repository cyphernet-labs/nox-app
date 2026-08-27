import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/chat/wire/chat_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/chats_wire_entity.dart';

void main() {
  final json = <String, dynamic>{
    'chat_id': 'c_9f2',
    'name': 'Kitchen talks',
    'created_at': 1755600000,
    'created_by_label': 'Anna',
    'last_message_preview': 'see you there',
    'last_activity_at': 1755600123,
  };

  group('ChatWireEntity (contract v0 §4)', () {
    test('parses the full contract shape 1:1', () {
      final entity = ChatWireEntity.fromJson(json);

      expect(entity.chatId, 'c_9f2');
      expect(entity.name, 'Kitchen talks');
      expect(entity.createdAt, 1755600000);
      expect(entity.createdByLabel, 'Anna');
      expect(entity.lastMessagePreview, 'see you there');
      expect(entity.lastActivityAt, 1755600123);
    });

    test('serializes back with the exact contract keys and no local fields', () {
      final out = ChatWireEntity.fromJson(json).toJson();

      expect(out['chat_id'], 'c_9f2');
      expect(out['created_at'], 1755600000);
      expect(out['created_by_label'], 'Anna');
      expect(out['last_activity_at'], 1755600123);
      // The unread counter is device-local (§8.3) - never on the wire.
      expect(out.containsKey('unread_count'), isFalse);
    });

    test('unknown sibling fields are ignored (v0 evolves)', () {
      final withExtra = Map<String, dynamic>.from(json)..['future_field'] = true;
      expect(() => ChatWireEntity.fromJson(withExtra), returnsNormally);
    });
  });

  group('ChatsWireEntity page (contract v0 §4)', () {
    test('parses {chats, has_more} and defaults an absent list to empty', () {
      final page = ChatsWireEntity.fromJson(<String, dynamic>{
        'chats': [json],
        'has_more': true,
      });
      expect(page.chats.single.chatId, 'c_9f2');
      expect(page.hasMore, isTrue);

      final empty = ChatsWireEntity.fromJson(<String, dynamic>{'has_more': false});
      expect(empty.chats, isEmpty);
      expect(empty.hasMore, isFalse);
    });

    test('round-trips through the ResponseEntity envelope registry', () {
      final envelope = ResponseEntity<ChatsWireEntity>(
        success: true,
        data: ChatsWireEntity(chats: [ChatWireEntity.fromJson(json)], hasMore: false),
      );
      final parsed = ResponseEntity<ChatsWireEntity>.fromJson(envelope.toJson());
      expect(parsed.data, envelope.data);
    });
  });
}
