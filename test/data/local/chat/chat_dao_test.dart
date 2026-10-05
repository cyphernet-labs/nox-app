import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/entity/chat/chat_entity.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/local/chat/chat_dao.dart';
import 'package:sembast/sembast.dart';

void main() {
  late AppDatabase appDb;
  late ChatDao dao;

  setUp(() async {
    appDb = AppDatabaseTest();
    await appDb.clearEntireDatabase();
    dao = ChatDao(appDb);
  });

  ChatEntity chat(String id, String name, String iso) =>
      ChatEntity(id: id, name: name, lastMessagePreview: '', lastMessageAt: iso, unreadCount: 0, lastOpenedSeq: null);

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
    // Write a genuinely undecodable row straight into the store the DAO reads (missing
    // the required fields ChatEntity.fromJson coerces), alongside one valid chat.
    final db = await appDb.db;
    await stringMapStoreFactory.store('chats').record('broken').put(db, <String, dynamic>{'garbage': true});
    await dao.upsert(chat('good', 'Good', '2026-01-01T00:00:00.000Z'));

    // The decode guard drops the broken row and returns only the valid one — it does
    // not throw and tear down the whole list read.
    expect((await dao.getAllSorted()).map((c) => c.id).toList(), ['good']);
  });

  test('getById returns a stored chat and null for an absent id', () async {
    await dao.upsert(chat('a', 'Alpha', '2026-01-01T00:00:00.000Z'));
    expect((await dao.getById('a'))?.name, 'Alpha');
    expect(await dao.getById('missing'), isNull);
  });

  group('read marks (031)', () {
    test('the mark moves forward only, and 0 is a real mark rather than none', () async {
      await dao.upsert(chat('m', 'Marked', '2026-01-01T00:00:00.000Z'));

      // Opening a chat whose cache is empty marks 0. That is a real open: any
      // history arriving later was genuinely never seen. Treating it as "no
      // mark" would leave the chat permanently badge-less.
      await dao.advanceReadMark(chatId: 'm', seq: 0, ceiling: 0);
      expect((await dao.getById('m'))!.lastOpenedSeq, 0);

      await dao.advanceReadMark(chatId: 'm', seq: 7, ceiling: 7);
      expect((await dao.getById('m'))!.lastOpenedSeq, 7);

      // Backwards is refused: a badge must not resurrect messages already seen.
      await dao.advanceReadMark(chatId: 'm', seq: 3, ceiling: 7);
      expect((await dao.getById('m'))!.lastOpenedSeq, 7);
    });

    test('the mark is clamped to the ceiling, so a foreign seq space cannot poison it', () async {
      await dao.upsert(chat('p', 'Poison', '2026-01-01T00:00:00.000Z'));

      // A clock-derived seq sits fifteen digits above any journal number. The
      // mark only moves forward, so following it there would put this chat's
      // badge permanently out of reach of every real event.
      await dao.advanceReadMark(chatId: 'p', seq: 1788000000000000, ceiling: 12);
      expect((await dao.getById('p'))!.lastOpenedSeq, 12);
    });

    test('clearReadMarks drops the marks and leaves the rest of the row alone', () async {
      await dao.upsert(chat('a', 'Alpha', '2026-01-01T00:00:00.000Z'));
      await dao.advanceReadMark(chatId: 'a', seq: 5, ceiling: 5);

      await dao.clearReadMarks();

      final after = (await dao.getById('a'))!;
      expect(after.lastOpenedSeq, isNull);
      expect(after.name, 'Alpha');
      expect(after.lastMessageAt, '2026-01-01T00:00:00.000Z');
    });

    test('a write carrying an older mark does not put back one advanced in between', () async {
      // A page of chats read the row, the chat was opened, then the page was
      // written: the mark it carried is from before the open. Putting it back
      // brought badges back for messages already seen.
      await dao.upsert(chat('a', 'Alpha', '2026-01-01T00:00:00.000Z'));
      final readBefore = (await dao.getById('a'))!;
      await dao.advanceReadMark(chatId: 'a', seq: 9, ceiling: 9);

      await dao.saveData([readBefore.copyWith(name: 'Alpha (from the server)')]);
      await dao.upsert(readBefore.copyWith(lastMessagePreview: 'new'));

      final after = (await dao.getById('a'))!;
      expect(after.lastOpenedSeq, 9);
      expect(after.lastMessagePreview, 'new', reason: 'the rest of the write still lands');
    });

    test('a write may still move the mark forward', () async {
      await dao.upsert(chat('a', 'Alpha', '2026-01-01T00:00:00.000Z').copyWith(lastOpenedSeq: 3));

      await dao.upsert(chat('a', 'Alpha', '2026-01-01T00:00:00.000Z').copyWith(lastOpenedSeq: 8));

      expect((await dao.getById('a'))!.lastOpenedSeq, 8);
    });
  });

  group('chats waiting for the server (phase 041)', () {
    test('pendingCreations lists only the chats waiting to be created, the oldest first', () async {
      await dao.upsert(chat('c_new', 'New', '2026-01-03T00:00:00.000Z').copyWith(creation: 'pending', createdAt: 300));
      await dao.upsert(chat('c_old', 'Old', '2026-01-01T00:00:00.000Z').copyWith(creation: 'pending', createdAt: 100));
      await dao.upsert(chat('c_taken', 'Taken', '2026-01-02T00:00:00.000Z').copyWith(creation: 'name_taken', createdAt: 200));
      await dao.upsert(chat('c_server', 'Server', '2026-01-04T00:00:00.000Z'));

      expect((await dao.pendingCreations()).map((c) => c.id), ['c_old', 'c_new']);
    });

    test('update changes one chat and keeps the rest of it', () async {
      await dao.upsert(chat('c1', 'Kitchen', '2026-01-01T00:00:00.000Z').copyWith(creation: 'pending'));
      await dao.advanceReadMark(chatId: 'c1', seq: 4, ceiling: 4);

      final written = await dao.update('c1', (c) => c.copyWith(creation: 'name_taken', creationAttempts: 2));

      expect(written?.creation, 'name_taken');
      final stored = (await dao.getById('c1'))!;
      expect(stored.creationAttempts, 2);
      expect(stored.lastOpenedSeq, 4, reason: 'the read mark is not the update\'s to touch');
      expect(stored.name, 'Kitchen');
    });

    test('update of a chat that is not there writes nothing', () async {
      expect(await dao.update('nobody', (c) => c.copyWith(name: 'x')), isNull);
      expect(await dao.count(), 0);
    });

    test('delete removes one chat', () async {
      await dao.upsert(chat('a', 'A', '2026-01-01T00:00:00.000Z'));
      await dao.upsert(chat('b', 'B', '2026-01-02T00:00:00.000Z'));

      await dao.delete('a');

      expect((await dao.getAllSorted()).map((c) => c.id), ['b']);
    });
  });
}
