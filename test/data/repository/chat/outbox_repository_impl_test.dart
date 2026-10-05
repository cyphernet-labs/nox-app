import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/outbox_status.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/model/file/unfinished_upload.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The same handle, the moment compared as a moment: the store hands the domain
/// local wall-clock time, as it does for every other timestamp.
Matcher _same(UnfinishedUpload expected) => isA<UnfinishedUpload>()
    .having((u) => u.fileId, 'fileId', expected.fileId)
    .having((u) => u.sourceSize, 'sourceSize', expected.sourceSize)
    .having((u) => u.sourceModifiedAt.isAtSameMomentAs(expected.sourceModifiedAt), 'same moment', isTrue);

/// The queue's whole reason to exist is that the idempotency key is minted at
/// enqueue time and stored with the record. These tests hold that line.
void main() {
  late OutboxRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase();
    repository = getIt<OutboxRepository>();
  });

  tearDown(() async => getIt.reset());

  test('enqueue mints a unique key and persists the record before returning', () async {
    final first = (await repository.enqueue(chatId: 'c1', text: 'one')).data!;
    final second = (await repository.enqueue(chatId: 'c1', text: 'two')).data!;

    expect(first.clientMessageId, isNotEmpty);
    expect(first.clientMessageId, isNot(second.clientMessageId));
    // Persisted, not just returned: a key that only exists in memory is the
    // defect this feature removes.
    expect((await repository.pending()).map((e) => e.clientMessageId), [first.clientMessageId, second.clientMessageId]);
  });

  test('the queue comes back in send order across chats', () async {
    final a = (await repository.enqueue(chatId: 'c1', text: 'a')).data!;
    final b = (await repository.enqueue(chatId: 'c2', text: 'b')).data!;
    final c = (await repository.enqueue(chatId: 'c1', text: 'c')).data!;

    expect((await repository.pending()).map((e) => e.clientMessageId).toList(), [a.clientMessageId, b.clientMessageId, c.clientMessageId]);
  });

  test('an attachment survives the round trip, local path included', () async {
    AppClock.freeze(DateTime(2026, 6, 15, 21, 30));
    addTearDown(AppClock.reset);
    final attachment = MessageAttachment(
      id: 'f1',
      type: FileType.image,
      name: 'shot.png',
      sizeBytes: 2048,
      mime: 'image/png',
      localPath: '/tmp/shot.png',
      expiresAt: AppClock.now().add(const Duration(days: 7)),
    );

    final stored = (await repository.enqueue(chatId: 'c1', attachment: attachment)).data!;
    final read = (await repository.pending()).single;

    expect(read.clientMessageId, stored.clientMessageId);
    expect(read.text, isNull);
    expect(read.attachment?.name, 'shot.png');
    expect(read.attachment?.mime, 'image/png');
    // The device path is the client's half of the contract — the wire never
    // carries it, so only the queue can bring it back after a restart.
    expect(read.attachment?.localPath, '/tmp/shot.png');
    expect(read.attachment?.expiresAt, isNotNull);
  });

  test('a retryable failure counts the attempt but leaves the entry queued', () async {
    final entry = (await repository.enqueue(chatId: 'c1', text: 'x')).data!;

    await repository.recordFailure(clientMessageId: entry.clientMessageId, code: 'connection', terminal: false, serverAnswered: false);

    final after = (await repository.pending()).single;
    expect(after.status, OutboxStatus.pending); // still on its way
    // The count HAS to grow here, or the pause between retries never grows.
    expect(after.attempts, 1);
    expect(after.lastErrorCode, 'connection');
  });

  test('a terminal failure moves the entry to error and out of the drain\'s input', () async {
    final entry = (await repository.enqueue(chatId: 'c1', text: 'x')).data!;

    await repository.recordFailure(clientMessageId: entry.clientMessageId, code: 'payloadTooLarge', terminal: true, serverAnswered: true);

    expect(await repository.pending(), isEmpty); // nothing will retry it
    final queued = await repository.watchQueue().first;
    expect(queued.single.status, OutboxStatus.error); // but it is still shown
  });

  test('a manual retry re-queues and starts the ladder over', () async {
    final entry = (await repository.enqueue(chatId: 'c1', text: 'x')).data!;
    await repository.recordFailure(clientMessageId: entry.clientMessageId, code: 'internal', terminal: false, serverAnswered: true);
    await repository.recordFailure(clientMessageId: entry.clientMessageId, code: 'payloadTooLarge', terminal: true, serverAnswered: true);

    await repository.markPending(clientMessageId: entry.clientMessageId);

    final after = (await repository.pending()).single;
    expect(after.status, OutboxStatus.pending);
    // A tap means "try again now": the pause goes back to its shortest and the
    // automatic retries are replenished. Keeping the spent counters would make
    // every later tap a single shot that fails straight back to error.
    expect(after.attempts, 0);
    expect(after.refusals, 0);
  });

  test('a dead channel raises attempts but not refusals — only the server may spend the ladder', () async {
    final entry = (await repository.enqueue(chatId: 'c1', text: 'x')).data!;

    await repository.recordFailure(clientMessageId: entry.clientMessageId, code: 'connection', terminal: false, serverAnswered: false);
    await repository.recordFailure(clientMessageId: entry.clientMessageId, code: 'internal', terminal: false, serverAnswered: true);

    final after = (await repository.pending()).single;
    expect(after.attempts, 2); // both delay the next try
    expect(after.refusals, 1); // only the answered one counts towards giving up
  });

  test('marking a record that has already been sent is a no-op, not a crash', () async {
    // The drain can remove an entry while a slower failure path is still on its
    // way to marking it; that race must not take the app down.
    await repository.recordFailure(clientMessageId: 'gone', code: 'connection', terminal: false, serverAnswered: false);
    await repository.markPending(clientMessageId: 'gone');

    expect(await repository.pending(), isEmpty);
  });

  test('watchQueue narrows to a chat and emits the current queue on listen', () async {
    await repository.enqueue(chatId: 'c1', text: 'mine');
    await repository.enqueue(chatId: 'c2', text: 'other');

    expect((await repository.watchQueue(chatId: 'c1').first).single.text, 'mine');
  });

  test('removeForChat drops one chat\'s queue; clean empties all of it', () async {
    await repository.enqueue(chatId: 'c1', text: 'a');
    await repository.enqueue(chatId: 'c2', text: 'b');

    await repository.removeForChat(chatId: 'c1');
    expect((await repository.pending()).single.text, 'b');

    await repository.clean();
    expect(await repository.pending(), isEmpty);
  });

  test('moveChat carries a chat\'s queue to another id, keys and order kept, and leaves other chats alone', () async {
    // A server older than phase 041 answered a create with its own id: the
    // messages written into the chat follow it.
    final first = (await repository.enqueue(chatId: 'c_local', text: 'one')).data!;
    final other = (await repository.enqueue(chatId: 'c_other', text: 'elsewhere')).data!;
    final second = (await repository.enqueue(chatId: 'c_local', text: 'two')).data!;

    await repository.moveChat(from: 'c_local', to: 'c_server');

    final moved = await repository.watchQueue(chatId: 'c_server').first;
    expect(moved.map((e) => e.clientMessageId), [first.clientMessageId, second.clientMessageId]);
    expect(await repository.watchQueue(chatId: 'c_local').first, isEmpty);
    expect((await repository.find(clientMessageId: other.clientMessageId))?.chatId, 'c_other');
  });

  group('the unfinished upload (phase 043)', () {
    final upload = UnfinishedUpload(fileId: 'f_77', sourceSize: 2048, sourceModifiedAt: DateTime.utc(2026, 10, 5, 9, 30));

    test('noteUpload remembers the handle, and the drain\'s input carries it', () async {
      final entry = (await repository.enqueue(chatId: 'c1', text: 'with a file')).data!;

      await repository.noteUpload(clientMessageId: entry.clientMessageId, upload: upload);

      expect((await repository.pending()).single.upload, _same(upload));
      expect((await repository.find(clientMessageId: entry.clientMessageId))!.upload, _same(upload));
      expect((await repository.watchQueue().first).single.upload, _same(upload));
    });

    test('noteUpload with null forgets it', () async {
      final entry = (await repository.enqueue(chatId: 'c1', text: 'with a file')).data!;
      await repository.noteUpload(clientMessageId: entry.clientMessageId, upload: upload);

      await repository.noteUpload(clientMessageId: entry.clientMessageId, upload: null);

      expect((await repository.pending()).single.upload, isNull);
    });

    test('confirmed bytes forget it: there is nothing left to continue', () async {
      final entry = (await repository.enqueue(chatId: 'c1', text: 'with a file')).data!;
      await repository.noteUpload(clientMessageId: entry.clientMessageId, upload: upload);

      await repository.attachFile(clientMessageId: entry.clientMessageId, fileId: 'f_77');

      final read = (await repository.pending()).single;
      expect(read.fileId, 'f_77');
      expect(read.upload, isNull);
    });

    test('a failure and a manual retry keep it - the retry goes on from the server\'s bytes', () async {
      final entry = (await repository.enqueue(chatId: 'c1', text: 'with a file')).data!;
      await repository.noteUpload(clientMessageId: entry.clientMessageId, upload: upload);

      await repository.recordFailure(clientMessageId: entry.clientMessageId, code: 'internal', terminal: true, serverAnswered: true);
      expect((await repository.find(clientMessageId: entry.clientMessageId))!.upload, _same(upload));

      await repository.markPending(clientMessageId: entry.clientMessageId);
      expect((await repository.pending()).single.upload, _same(upload));
    });
  });
}
