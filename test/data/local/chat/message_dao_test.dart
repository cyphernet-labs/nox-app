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

  MessageEntity msg(String id, String chatId, String iso, {int? seq}) => MessageEntity(
    id: id,
    chatId: chatId,
    seq: seq,
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

  MessageEntity from(String id, String chatId, int seq, String author) => MessageEntity(
    id: id,
    chatId: chatId,
    seq: seq,
    authorId: author,
    authorLabel: author,
    text: 't',
    sentAt: '2026-06-01T00:00:00.000Z',
    status: 'sent',
    isSystem: false,
    attachmentId: null,
    attachmentType: null,
    attachmentName: null,
    attachmentSizeBytes: null,
  );

  group('countUnreadByChat', () {
    test('counts only what arrived above each chat\'s own mark', () async {
      await dao.saveData([
        from('m1', 'c1', 1, 'other'),
        from('m2', 'c1', 2, 'other'),
        from('m3', 'c1', 3, 'other'),
        from('m4', 'c2', 7, 'other'),
      ]);

      final counts = await dao.countUnreadByChat(marks: {'c1': 1, 'c2': 9}, excludeAuthors: const {});

      expect(counts['c1'], 2, reason: 'seq 2 and 3 sit above the mark, seq 1 does not');
      expect(counts['c2'], isNull, reason: 'nothing above the mark is no entry, which reads as zero');
    });

    test('a chat with no mark is absent, because an unopened chat shows no badge', () async {
      await dao.saveData([from('m1', 'c1', 1, 'other')]);

      final counts = await dao.countUnreadByChat(marks: const {}, excludeAuthors: const {});

      expect(counts, isEmpty);
    });

    test('our own messages never count, whichever id this device stamped', () async {
      // The identity resolver falls back to the login identifier before the
      // server-minted id is known, so both have to be excluded or a restart
      // mid-send raises a badge against yourself.
      await dao.saveData([from('m1', 'c1', 2, 'u_me'), from('m2', 'c1', 3, 'login-identifier'), from('m3', 'c1', 4, 'someone')]);

      final counts = await dao.countUnreadByChat(marks: {'c1': 1}, excludeAuthors: {'u_me', 'login-identifier'});

      expect(counts['c1'], 1);
    });

    test('a row with no seq has no place in the order and is not counted', () async {
      await dao.saveData([msg('pending', 'c1', '2026-06-05T00:00:00.000Z'), from('m1', 'c1', 5, 'other')]);

      final counts = await dao.countUnreadByChat(marks: {'c1': 1}, excludeAuthors: const {});

      expect(counts['c1'], 1);
    });

    test('one call answers for every chat at once', () async {
      await dao.saveData([from('m1', 'c1', 2, 'other'), from('m2', 'c2', 2, 'other'), from('m3', 'c3', 2, 'other')]);

      final counts = await dao.countUnreadByChat(marks: {'c1': 1, 'c2': 1, 'c3': 5}, excludeAuthors: const {});

      expect(counts['c1'], 1);
      expect(counts['c2'], 1);
      expect(counts['c3'], isNull);
    });
  });

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

  test('seq is the primary order: same-second sentAt ties can never reorder rows against their seq', () async {
    // Unix-second wire precision makes same-second sentAt strings identical;
    // insertion order is adversarial (higher seq first) to prove the sort does
    // not fall back to store/insertion order (FR-001 / US1 scenario 3).
    const iso = '2026-06-15T21:30:00.000Z';
    await dao.saveData([
      msg('srv_b', 'c1', iso, seq: 1011),
      msg('srv_a', 'c1', iso, seq: 1010),
      msg('srv_c', 'c1', '2026-06-15T21:29:00.000Z', seq: 1012), // seq beats an EARLIER sentAt too
    ]);

    expect((await dao.getByChatSorted('c1')).map((m) => m.seq).toList(), [1010, 1011, 1012]);
  });

  test('legacy pre-025 rows (no seq) order by sentAt before real-seq rows and ties total-order by id', () async {
    const iso = '2026-06-01T00:00:00.000Z';
    await dao.saveData([
      msg('new', 'c1', '2026-06-02T00:00:00.000Z', seq: 500),
      msg('leg_b', 'c1', iso), // seq null -> 0: the legacy block sorts first,
      msg('leg_a', 'c1', iso), // by sentAt, then by id for a deterministic tie
    ]);

    expect((await dao.getByChatSorted('c1')).map((m) => m.id).toList(), ['leg_a', 'leg_b', 'new']);
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
