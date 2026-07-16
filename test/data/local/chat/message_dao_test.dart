import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/entity/chat/message_entity.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/local/chat/message_dao.dart';

void main() {
  late MessageDao dao;

  setUp(() async {
    final db = AppDatabaseTest();
    await db.clearEntireDatabase();
    dao = MessageDao(db);
  });

  MessageEntity msg(String id, String chatId, String iso) => MessageEntity(
    id: id,
    chatId: chatId,
    authorId: 'u',
    authorLabel: 'U',
    text: 't',
    sentAt: iso,
    status: 'sent',
    isSystem: false,
    attachmentId: null,
    attachmentType: null,
    attachmentName: null,
    attachmentSizeBytes: null,
  );

  test('getByChatSorted returns a chat\'s messages chronological + counts per chat', () async {
    await dao.saveData([
      msg('b', 'c1', '2026-06-02T00:00:00.000Z'),
      msg('a', 'c1', '2026-06-01T00:00:00.000Z'),
      msg('x', 'c2', '2026-06-03T00:00:00.000Z'),
    ]);

    expect((await dao.getByChatSorted('c1')).map((m) => m.id).toList(), ['a', 'b']); // oldest first
    expect(await dao.countByChat('c1'), 2);
    expect(await dao.countByChat('c2'), 1);
  });

  test('upsert adds a message and cleanData empties the store', () async {
    await dao.upsert(msg('a', 'c1', '2026-06-01T00:00:00.000Z'));
    expect(await dao.countByChat('c1'), 1);

    await dao.cleanData();
    expect(await dao.countByChat('c1'), 0);
  });
}
