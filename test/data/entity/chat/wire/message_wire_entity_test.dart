import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/chat/wire/message_wire_entity.dart';

void main() {
  group('MessageWireEntity (contract v0 §5)', () {
    final json = <String, dynamic>{
      'message_id': 'm_51c',
      'seq': 1042,
      'chat_id': 'c_9f2',
      'author_id': 'u_3f2a1c9d40b7e518',
      'author_label': 'Anna',
      'client_message_id': '3f0e-uuid',
      'sent_at': 1755600123,
      'body': {'type': 'text', 'text': 'hello there'},
      'attachment': {'file_id': 'f_77', 'name': 'report.pdf', 'size': 123456, 'mime': 'application/pdf', 'expires_at': 1758200000},
    };

    test('parses the full contract shape 1:1', () {
      final entity = MessageWireEntity.fromJson(json);

      expect(entity.messageId, 'm_51c');
      expect(entity.seq, 1042);
      expect(entity.chatId, 'c_9f2');
      expect(entity.authorId, 'u_3f2a1c9d40b7e518');
      expect(entity.authorLabel, 'Anna');
      expect(entity.clientMessageId, '3f0e-uuid');
      expect(entity.sentAt, 1755600123);
      expect(entity.body!.type, 'text');
      expect(entity.body!.text, 'hello there');
      expect(entity.attachment!.fileId, 'f_77');
      expect(entity.attachment!.name, 'report.pdf');
      expect(entity.attachment!.size, 123456);
      expect(entity.attachment!.mime, 'application/pdf');
      expect(entity.attachment!.expiresAt, 1758200000);
    });

    test('serializes back with the exact contract keys', () {
      final entity = MessageWireEntity.fromJson(json);
      final out = entity.toJson();
      out['body'] = entity.body!.toJson();
      out['attachment'] = entity.attachment!.toJson();

      expect(out['message_id'], 'm_51c');
      expect(out['seq'], 1042);
      expect(out['chat_id'], 'c_9f2');
      expect(out['client_message_id'], '3f0e-uuid');
      expect(out['sent_at'], 1755600123);
      expect((out['attachment'] as Map<String, dynamic>)['file_id'], 'f_77');
      expect((out['attachment'] as Map<String, dynamic>)['size'], 123456);
      expect((out['attachment'] as Map<String, dynamic>)['expires_at'], 1758200000);
      // Local-only concepts never serialize: no status, no is_system, no localPath.
      expect(out.containsKey('status'), isFalse);
      expect(out.containsKey('is_system'), isFalse);
    });

    test('client_message_id, body and attachment are all optional (another author, attachment-only)', () {
      final minimal = MessageWireEntity.fromJson(<String, dynamic>{
        'message_id': 'm_1',
        'seq': 7,
        'chat_id': 'c_1',
        'author_id': 'Bob',
        'author_label': 'Bob',
        'sent_at': 1755600000,
      });

      expect(minimal.clientMessageId, isNull);
      expect(minimal.body, isNull);
      expect(minimal.attachment, isNull);
    });

    test('unknown sibling fields are ignored (v0 evolves)', () {
      final withExtra = Map<String, dynamic>.from(json)..['brand_new_field'] = 42;
      expect(() => MessageWireEntity.fromJson(withExtra), returnsNormally);
    });

    test('a non-text body type parses opaquely (the Q1 blob seam)', () {
      final blob = Map<String, dynamic>.from(json)..['body'] = {'type': 'blob', 'data': 'AAAA'};
      final entity = MessageWireEntity.fromJson(blob);
      expect(entity.body!.type, 'blob');
      expect(entity.body!.text, isNull);
    });

    test('round-trips through the ResponseEntity envelope registry', () {
      final envelope = ResponseEntity<MessageWireEntity>(success: true, data: MessageWireEntity.fromJson(json));
      final parsed = ResponseEntity<MessageWireEntity>.fromJson(envelope.toJson());
      expect(parsed.data, envelope.data);
    });
  });
}
