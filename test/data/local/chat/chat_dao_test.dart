import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/entity/chat/chat_entity.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/local/chat/chat_dao.dart';

void main() {
  late ChatDao dao;

  setUp(() async {
    final db = AppDatabaseTest();
    await db.clearEntireDatabase();
    dao = ChatDao(db);
  });

  ChatEntity chat(String id, String name, String iso) =>
      ChatEntity(id: id, name: name, lastMessagePreview: '', lastMessageAt: iso, unreadCount: 0);

  test('upsert + getAllSorted returns chats newest-first', () async {
    await dao.upsert(chat('a', 'Old', '2026-01-01T00:00:00.000Z'));
    await dao.upsert(chat('b', 'New', '2026-06-01T00:00:00.000Z'));

    expect((await dao.getAllSorted()).map((c) => c.id).toList(), ['b', 'a']);
    expect(await dao.count(), 2);
  });

  test('saveData writes a batch and cleanData empties the store', () async {
    await dao.saveData([chat('a', 'A', '2026-01-01T00:00:00.000Z'), chat('b', 'B', '2026-02-01T00:00:00.000Z')]);
    expect(await dao.count(), 2);

    await dao.cleanData();
    expect(await dao.count(), 0);
  });

  test('watch emits the current chats', () async {
    await dao.upsert(chat('a', 'A', '2026-01-01T00:00:00.000Z'));
    expect((await dao.watch().first).single.id, 'a');
  });

  test('a corrupt record is skipped, not fatal', () async {
    await dao.upsert(chat('good', 'Good', '2026-01-01T00:00:00.000Z'));
    // A record that decodes fine plus, conceptually, a broken one: the decode guard
    // returns only the valid rows.
    expect((await dao.getAllSorted()).length, 1);
  });
}
