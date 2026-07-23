import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/chat/wire/message_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/messages_wire_entity.dart';

void main() {
  const withAttachment = MessageWireEntity(
    id: 'm1',
    chatId: 'chat_0',
    authorId: 'u',
    authorLabel: 'Aria',
    text: 'see file',
    sentAt: '2026-06-15T21:30:00.000Z',
    status: 'sent',
    isSystem: false,
    attachment: MessageAttachmentWireEntity(id: 'a1', type: 'pdf', name: 'design-spec.pdf', sizeBytes: 2400000),
  );
  const noAttachment = MessageWireEntity(
    id: 'm0',
    chatId: 'chat_0',
    authorId: 'sys',
    authorLabel: 'System',
    text: 'Chat created',
    sentAt: '2026-06-15T20:00:00.000Z',
    status: 'none',
    isSystem: true,
  );
  const page = MessagesWireEntity(items: [noAttachment, withAttachment], page: 1, pageSize: 20, total: 2);

  test('MessageWireEntity round-trips with a nested attachment', () {
    expect(MessageWireEntity.fromJson(withAttachment.toJson()), withAttachment);
    expect(withAttachment.toJson()['attachment']['size_bytes'], 2400000);
  });

  test('MessageWireEntity round-trips without an attachment (null nested)', () {
    expect(MessageWireEntity.fromJson(noAttachment.toJson()), noAttachment);
    expect(noAttachment.toJson()['attachment'], isNull);
  });

  test('MessagesWireEntity round-trips its item list', () {
    expect(MessagesWireEntity.fromJson(page.toJson()), page);
  });

  test('ResponseEntity<MessagesWireEntity>.fromJson resolves data via the registry', () {
    final parsed = ResponseEntity<MessagesWireEntity>.fromJson(ResponseEntity<MessagesWireEntity>(success: true, data: page).toJson());
    expect(parsed.data, page);
  });
}
