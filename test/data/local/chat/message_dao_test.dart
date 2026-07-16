import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/entity/chat/message_entity.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/local/chat/message_dao.dart';
import 'package:sembast/sembast.dart';

void main() {
  late AppDatabase appDb;
  late MessageDao dao;

  setUp(() async {
    appDb = AppDatabaseTest();
    await appDb.clearEntireDatabase();
    dao = MessageDao(appDb);
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

  test('a corrupt record is skipped, not fatal', () async {
    // Write a genuinely undecodable row straight into the store the DAO reads (missing
    // the required fields MessageEntity.fromJson coerces), alongside a valid message in
    // the same chat.
    final db = await appDb.db;
    await stringMapStoreFactory.store('messages').record('broken').put(db, <String, dynamic>{'chatId': 'c1', 'garbage': true});
    await dao.upsert(msg('good', 'c1', '2026-06-01T00:00:00.000Z'));

    // The decode guard drops the broken row and returns only the valid message — it
    // does not throw and tear down the chat thread read.
    expect((await dao.getByChatSorted('c1')).map((m) => m.id).toList(), ['good']);
  });
}
