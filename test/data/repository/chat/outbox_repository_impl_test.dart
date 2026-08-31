import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/outbox_status.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
