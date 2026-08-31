import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/entity/chat/outbox_entity.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/local/chat/outbox_dao.dart';
import 'package:sembast/sembast.dart';

void main() {
  late AppDatabase appDb;
  late OutboxDao dao;

  setUp(() async {
    appDb = AppDatabaseTest();
    await appDb.clearEntireDatabase();
    dao = OutboxDao(appDb);
  });

  OutboxEntity entry(String id, {String chatId = 'c1', String createdAt = '2026-06-15T21:30:00.000Z', String status = 'pending'}) =>
      OutboxEntity(clientMessageId: id, chatId: chatId, ordinal: 0, createdAt: createdAt, status: status, attempts: 0, text: 't');

  test('enqueue appends in call order and getAllSorted returns that order back', () async {
    for (final id in ['a', 'b', 'c']) {
      await dao.enqueue(entry(id));
    }

    expect((await dao.getAllSorted()).map((e) => e.clientMessageId).toList(), ['a', 'b', 'c']);
    expect((await dao.getAllSorted()).map((e) => e.ordinal).toList(), [1, 2, 3]);
  });

  test('order survives a restart: a fresh DAO over the same store keeps counting up', () async {
    await dao.enqueue(entry('first'));
    await dao.enqueue(entry('second'));

    // A new DAO instance is the closest a unit test gets to relaunching the
    // app: the counter has to live in the store, not in the object.
    final reopened = OutboxDao(appDb);
    await reopened.enqueue(entry('third'));

    expect((await reopened.getAllSorted()).map((e) => e.clientMessageId).toList(), ['first', 'second', 'third']);
  });

  test('a same-millisecond burst still has a defined order (the clock cannot break the tie)', () async {
    // Goldens freeze the clock, so identical createdAt is the NORMAL case, not
    // an edge one — ordering by time would leave these three unordered.
    const frozen = '2026-06-15T21:30:00.000Z';
    await dao.enqueue(entry('x', createdAt: frozen));
    await dao.enqueue(entry('y', createdAt: frozen));
    await dao.enqueue(entry('z', createdAt: frozen));

    expect((await dao.getAllSorted()).map((e) => e.clientMessageId).toList(), ['x', 'y', 'z']);
  });

  test('re-enqueuing the same key replaces the row instead of adding a second one', () async {
    // The record key IS the idempotency key: this is the structural guarantee
    // that a duplicate cannot exist, not a check somebody has to remember.
    await dao.enqueue(entry('same'));
    await dao.enqueue(entry('same'));

    expect(await dao.getAllSorted(), hasLength(1));
  });

  test('getByChat and watch narrow to one chat, in send order', () async {
    await dao.enqueue(entry('a1', chatId: 'c1'));
    await dao.enqueue(entry('b1', chatId: 'c2'));
    await dao.enqueue(entry('a2', chatId: 'c1'));

    expect((await dao.getAllSorted(chatId: 'c1')).map((e) => e.clientMessageId).toList(), ['a1', 'a2']);
    expect((await dao.watch(chatId: 'c2').first).map((e) => e.clientMessageId).toList(), ['b1']);
  });

  test('watch emits the current queue on listen — that is what restores it after a restart', () async {
    await dao.enqueue(entry('waiting'));

    expect((await dao.watch().first).single.clientMessageId, 'waiting');
  });

  test('updateIfPresent rewrites a record in place and remove drops exactly one', () async {
    final stored = await dao.enqueue(entry('e'));
    await dao.enqueue(entry('keep'));

    final applied = await dao.updateIfPresent('e', (c) => c.copyWith(status: 'error', attempts: 3, lastErrorCode: 'payloadTooLarge'));
    expect(applied, isTrue);
    final read = await dao.getById('e');
    expect(read?.status, 'error');
    expect(read?.attempts, 3);
    expect(read?.ordinal, stored.ordinal); // the rewrite must not reshuffle the queue

    await dao.remove('e');
    expect((await dao.getAllSorted()).map((e) => e.clientMessageId).toList(), ['keep']);
  });

  test('updateIfPresent will not resurrect a record that was discarded', () async {
    // A plain get-then-put would write the row back and the drain would send a
    // message the user was already told is gone.
    await dao.enqueue(entry('discarded'));
    await dao.remove('discarded');

    final applied = await dao.updateIfPresent('discarded', (c) => c.copyWith(status: 'error'));

    expect(applied, isFalse);
    expect(await dao.getAllSorted(), isEmpty);
  });

  test('two concurrent enqueues get two different positions', () async {
    // The max-scan and the write share a transaction precisely so that this
    // cannot hand both callers the same ordinal and leave the order undefined.
    final placed = await Future.wait([dao.enqueue(entry('a')), dao.enqueue(entry('b')), dao.enqueue(entry('c'))]);

    expect(placed.map((e) => e.ordinal).toSet(), hasLength(3));
    expect((await dao.getAllSorted()), hasLength(3));
  });

  test('removeForChat drops one chat\'s queue and leaves the others alone', () async {
    await dao.enqueue(entry('a', chatId: 'c1'));
    await dao.enqueue(entry('b', chatId: 'c2'));

    await dao.removeForChat('c1');

    expect((await dao.getAllSorted()).map((e) => e.clientMessageId).toList(), ['b']);
  });

  test('cleanData empties the store — the queue holds texts, so logout takes it', () async {
    await dao.enqueue(entry('a'));
    await dao.cleanData();

    expect(await dao.getAllSorted(), isEmpty);
  });

  test('a corrupt record is skipped, not fatal', () async {
    // A row the entity cannot decode must not take the whole queue down with
    // it — the rest of the messages still have to be sent.
    final db = await appDb.db;
    await stringMapStoreFactory.store('outbox').record('broken').put(db, <String, dynamic>{'garbage': true});
    await dao.enqueue(entry('good'));

    expect((await dao.getAllSorted()).map((e) => e.clientMessageId).toList(), ['good']);
  });
}
