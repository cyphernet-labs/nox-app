import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/sync/outbox_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';
import 'package:nox_app/domain/model/chat/outbox_status.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outbox_service_test.mocks.dart';

/// A phase source the test drives by hand — the drain keys on the SESSION
/// phase, not on raw device connectivity, so this is the switch under test.
class _FakePhase implements SessionPhaseService {
  _FakePhase(this._phase);

  SessionPhase _phase;
  final StreamController<SessionPhase> _controller = StreamController<SessionPhase>.broadcast();

  @override
  SessionPhase get phase => _phase;

  @override
  Stream<SessionPhase> watchPhase() => _controller.stream;

  void emit(SessionPhase next) {
    _phase = next;
    _controller.add(next);
  }

  Future<void> dispose() => _controller.close();
}

/// A file repository the test drives by hand: it counts uploads, can run a hook
/// in the middle of one, and can be told to refuse. Nothing touches a disk or a
/// server.
class _FakeFiles implements FileRepository {
  int uploads = 0;
  RepositoryException? failure;
  Future<void> Function()? duringUpload;

  @override
  Future<RepositoryResult<String>> upload({required String path, required String mime, TransferFraction? onProgress}) async {
    uploads++;
    await duringUpload?.call();
    if (failure != null) return RepositoryResult<String>.error(exception: failure!);
    if (!File(path).existsSync()) return RepositoryResult<String>.error(exception: RepositoryException.notFound);
    onProgress?.call(1);
    return RepositoryResult<String>.success(data: 'f_fake_$uploads');
  }

  @override
  Future<RepositoryResult<String>> download({required String fileId, required String suggestedName, TransferFraction? onProgress}) async =>
      RepositoryResult<String>.success(data: '/tmp/$fileId');

  @override
  Future<String?> localPathFor({required String fileId, required String suggestedName}) async => null;

  @override
  Future<void> clean() async {}
}

/// The drain is the only sender in the app, so the properties asserted here —
/// strict order, one pass at a time, remove-after-persist, and a classification
/// that does not retry the unretryable — are the ones a duplicate or a lost
/// message would come from.
@GenerateMocks([MessageRepository])
void main() {
  late MockMessageRepository messages;
  late OutboxRepository outbox;
  late _FakePhase phase;
  late OutboxService service;
  late _FakeFiles files;
  late List<String> sentKeys;
  late List<String> sentAttachmentIds;

  /// Fails the SEND without touching the upload — the two are separate steps
  /// now, and a test that cannot tell them apart proves nothing about either.
  late RepositoryException? sendFailure;
  late Map<String, RepositoryException> failures;

  MessageModel echo(String chatId, String text) => MessageModel(
    id: 'srv_$text',
    chatId: chatId,
    authorId: 'me',
    authorLabel: 'Me',
    text: text,
    sentAt: AppClock.now(),
    status: MessageStatus.sent,
  );

  setUp(() async {
    AppClock.freeze(DateTime(2026, 6, 15, 21, 30));
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase();
    outbox = getIt<OutboxRepository>();
    provideDummy<RepositoryResult<MessageModel>>(RepositoryResult.error(exception: RepositoryException.unknown));

    sentKeys = <String>[];
    sentAttachmentIds = <String>[];
    failures = <String, RepositoryException>{};
    sendFailure = null;
    messages = MockMessageRepository();
    when(
      messages.sendMessage(
        chatId: anyNamed('chatId'),
        clientMessageId: anyNamed('clientMessageId'),
        text: anyNamed('text'),
        attachment: anyNamed('attachment'),
      ),
    ).thenAnswer((invocation) async {
      final key = invocation.namedArguments[#clientMessageId] as String;
      final text = invocation.namedArguments[#text] as String?;
      final attached = invocation.namedArguments[#attachment] as MessageAttachment?;
      sentKeys.add(key);
      if (attached != null) sentAttachmentIds.add(attached.id);
      final failure = failures[text] ?? sendFailure;
      if (failure != null) return RepositoryResult<MessageModel>.error(exception: failure);
      return RepositoryResult<MessageModel>.success(data: echo(invocation.namedArguments[#chatId] as String, text ?? ''));
    });

    files = _FakeFiles();
    phase = _FakePhase(SessionPhase.live);
    service = OutboxService(outbox, messages, phase, files);
  });

  tearDown(() async {
    await service.stop();
    await phase.dispose();
    AppClock.reset();
    await getIt.reset();
  });

  Future<List<String>> enqueue(List<String> texts) async {
    final keys = <String>[];
    for (final text in texts) {
      keys.add((await outbox.enqueue(chatId: 'c1', text: text)).data!.clientMessageId);
    }
    return keys;
  }

  test('the queue is drained strictly in order, and each accepted send leaves it', () async {
    // Ten, not two: order is only interesting once it could plausibly scramble.
    final texts = [for (var i = 0; i < 10; i++) 'm$i'];
    final keys = await enqueue(texts);

    await service.flush();

    expect(sentKeys, keys); // same order they were written in
    expect(await outbox.pending(), isEmpty);
  });

  test('two flushes at once do not send anything twice', () async {
    // A connectivity flap plus a fresh send is exactly this shape, and it is
    // what double-posted before the drain was serialised.
    await enqueue(['a', 'b']);

    await Future.wait([service.flush(), service.flush(), service.flush()]);

    expect(sentKeys.toSet(), hasLength(2));
    expect(sentKeys, hasLength(2));
  });

  test('a retryable refusal stops the pass so the queue cannot arrive out of order', () async {
    failures['b'] = RepositoryException.connection;
    final keys = await enqueue(['a', 'b', 'c']);

    await service.flush();

    // 'c' must NOT overtake the message stuck in front of it.
    expect(sentKeys, [keys[0], keys[1]]);
    final still = await outbox.pending();
    expect(still.map((e) => e.text), ['b', 'c']);
    expect(still.first.attempts, 1);
  });

  test('a refusal a retry cannot fix is marked and the pass continues past it', () async {
    // Otherwise one oversized message holds every later message hostage.
    failures['b'] = RepositoryException.payloadTooLarge;
    await enqueue(['a', 'b', 'c']);

    await service.flush();

    expect(sentKeys, hasLength(3));
    final left = await outbox.watchQueue().first;
    expect(left.single.text, 'b');
    expect(left.single.status, OutboxStatus.error);
    expect(await outbox.pending(), isEmpty); // nothing retries it on its own
  });

  test('an unrecognised failure is retried rather than declared dead', () async {
    // Same rule the contract applies to unknown error codes: guessing "give up"
    // would silently drop a message the user believes they sent.
    failures['a'] = RepositoryException.unknown;
    await enqueue(['a']);

    await service.flush();

    expect((await outbox.pending()).single.status, OutboxStatus.pending);
  });

  test('nothing is sent while the channel is down, and the attempt is not burned', () async {
    phase = _FakePhase(SessionPhase.disconnected);
    service = OutboxService(outbox, messages, phase, files);
    await enqueue(['a']);

    await service.flush();

    expect(sentKeys, isEmpty);
    // No failed attempt was recorded, so the backoff does not grow for a reason
    // that has nothing to do with the message.
    expect((await outbox.pending()).single.attempts, 0);
  });

  test('catching up is not live: the drain waits for the replay to finish', () async {
    phase = _FakePhase(SessionPhase.catchingUp);
    service = OutboxService(outbox, messages, phase, files);
    await enqueue(['a']);

    await service.flush();

    expect(sentKeys, isEmpty);
  });

  test('the channel going live drains the queue with no one asking', () async {
    phase = _FakePhase(SessionPhase.disconnected);
    service = OutboxService(outbox, messages, phase, files);
    service.start();
    await enqueue(['written while offline']);

    phase.emit(SessionPhase.live);
    for (var i = 0; i < 100 && sentKeys.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(sentKeys, hasLength(1));
    expect(await outbox.pending(), isEmpty);
  });

  test('start() twice does not open a second subscription (one live edge, one drain)', () async {
    phase = _FakePhase(SessionPhase.disconnected);
    service = OutboxService(outbox, messages, phase, files);
    service.start();
    service.start();
    await enqueue(['once']);

    phase.emit(SessionPhase.live);
    for (var i = 0; i < 100 && sentKeys.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(sentKeys, hasLength(1));
  });

  test('a pass that blows up does not end sending for the life of the process', () async {
    // `_queue.then(...)` on a rejected future stays rejected forever, so an
    // unabsorbed throw would silently stop every later drain — the same shape
    // as the halt that once silenced event sync.
    await enqueue(['a']);
    when(
      messages.sendMessage(
        chatId: anyNamed('chatId'),
        clientMessageId: anyNamed('clientMessageId'),
        text: anyNamed('text'),
        attachment: anyNamed('attachment'),
      ),
    ).thenThrow(StateError('the store blew up mid-pass'));

    await service.flush();
    expect(await outbox.pending(), hasLength(1)); // nothing was sent, nothing was lost

    // The next trigger has to get a real attempt.
    when(
      messages.sendMessage(
        chatId: anyNamed('chatId'),
        clientMessageId: anyNamed('clientMessageId'),
        text: anyNamed('text'),
        attachment: anyNamed('attachment'),
      ),
    ).thenAnswer((invocation) async {
      sentKeys.add(invocation.namedArguments[#clientMessageId] as String);
      return RepositoryResult<MessageModel>.success(data: echo('c1', 'a'));
    });

    await service.flush();
    expect(sentKeys, hasLength(1));
    expect(await outbox.pending(), isEmpty);
  });

  group('attachments', () {
    late File source;

    setUp(() async {
      source = File('${Directory.systemTemp.path}/nox_outbox_${DateTime.now().microsecondsSinceEpoch}.png')
        ..writeAsBytesSync(List<int>.filled(64, 7));
      addTearDown(() => source.existsSync() ? source.deleteSync() : null);
    });

    MessageAttachment picked() => MessageAttachment(
      id: 'att_local',
      type: FileType.image,
      name: 'shot.png',
      sizeBytes: 64,
      mime: 'image/png',
      localPath: source.path,
    );

    test('the bytes go up before the message names them, and the id is remembered', () async {
      final entry = (await outbox.enqueue(chatId: 'c1', text: null, attachment: picked())).data!;

      await service.flush();

      // The message went out naming the SERVER's id, not the composer's local
      // draft id — the latter means nothing to anyone else.
      expect(sentAttachmentIds.single, isNot('att_local'));
      expect(sentAttachmentIds.single, startsWith('f_'));
      expect(files.uploads, 1);
      expect(await outbox.pending(), isEmpty);
      expect(entry.fileId, isNull, reason: 'the snapshot taken at enqueue knew nothing yet');
    });

    test('a confirmed upload is not repeated when the send is retried', () async {
      // The whole point of remembering the id: a crash between the transfer and
      // the send must not push the bytes again.
      service.start(); // a live edge is what lifts the backoff pause between passes
      await outbox.enqueue(chatId: 'c1', text: null, attachment: picked());

      // First pass: the bytes go up, then the send fails retryably.
      sendFailure = RepositoryException.connection;
      await service.flush();
      expect(files.uploads, 1);
      expect((await outbox.pending()).single.fileId, isNotNull, reason: 'the confirmed id is remembered');

      // Second pass: the send works this time.
      sendFailure = null;
      phase.emit(SessionPhase.live);
      await service.flush();

      expect(files.uploads, 1, reason: 'the bytes were already there — do not push them again');
      expect(await outbox.pending(), isEmpty);
    });

    test('a file that vanished from disk fails this message and lets the queue move on', () async {
      await outbox.enqueue(chatId: 'c1', text: null, attachment: picked());
      final behind = (await outbox.enqueue(chatId: 'c1', text: 'behind it')).data!;
      source.deleteSync(); // the user cleared their photos between attach and drain

      await service.flush();

      final left = await outbox.watchQueue().first;
      expect(left.single.status, OutboxStatus.error);
      expect(sentKeys, contains(behind.clientMessageId), reason: 'one bad attachment must not hold the queue');
    });

    test('a message discarded during the upload is not sent', () async {
      // Phase 027 re-reads right before sending so a discard is honoured; an
      // upload stretches that window from milliseconds to minutes.
      final entry = (await outbox.enqueue(chatId: 'c1', text: null, attachment: picked())).data!;
      files.duringUpload = () async => outbox.remove(clientMessageId: entry.clientMessageId);

      await service.flush();

      expect(sentKeys, isEmpty, reason: 'the bytes may be up, but no message may name them');
      expect(await outbox.pending(), isEmpty);
    });
  });

  test('messages for chats nobody has open are sent all the same', () async {
    // The drain lives in the data layer precisely so that leaving the screen —
    // or never opening it — does not strand a message. No bloc exists in this
    // file at all, which is the point.
    final a = (await outbox.enqueue(chatId: 'chat_a', text: 'to a')).data!;
    final b = (await outbox.enqueue(chatId: 'chat_b', text: 'to b')).data!;

    await service.flush();

    expect(sentKeys, [a.clientMessageId, b.clientMessageId]);
    expect(await outbox.pending(), isEmpty);
  });

  test('stop() does not return while a send is in flight — logout must not wipe underneath a write', () async {
    // Hold the send open so "in flight" is a fact of the test, not a hope about
    // timing: the earlier version of this test passed even with the await in
    // stop() deleted, because the pass finished on its own first.
    final held = Completer<void>();
    when(
      messages.sendMessage(
        chatId: anyNamed('chatId'),
        clientMessageId: anyNamed('clientMessageId'),
        text: anyNamed('text'),
        attachment: anyNamed('attachment'),
      ),
    ).thenAnswer((invocation) async {
      sentKeys.add(invocation.namedArguments[#clientMessageId] as String);
      await held.future;
      return RepositoryResult<MessageModel>.success(data: echo('c1', 'held'));
    });
    await enqueue(['held']);

    unawaited(service.flush());
    await Future<void>.delayed(const Duration(milliseconds: 20)); // let the send start
    expect(sentKeys, hasLength(1)); // precondition: we are inside sendMessage

    var stopped = false;
    final stopping = service.stop().then((_) => stopped = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(stopped, isFalse, reason: 'stop() must not return while a write is still running');

    held.complete();
    await stopping;

    expect(stopped, isTrue);
    // The write finished before stop() returned, so the caller may now wipe.
    expect(await outbox.pending(), isEmpty);
  });

  test('a pass that has not started yet is abandoned by stop(), not sent into a wipe', () async {
    await enqueue(['a']);

    await service.stop();
    await service.flush(); // whatever was chained must not send now

    expect(sentKeys, isEmpty);
    // Nothing lost: the entry is still queued for whoever starts the drain next.
    expect(await outbox.pending(), hasLength(1));
  });

  test('a retryable refusal actually pauses: an immediate flush does not re-hit the head', () async {
    // Without the pause, every other trigger — a fresh send, a reconnect —
    // retries the stuck head at once, which makes the backoff decorative and
    // inflates the attempt count for a reason that has nothing to do with the
    // server.
    failures['a'] = RepositoryException.connection;
    await enqueue(['a']);

    await service.flush();
    expect(sentKeys, hasLength(1));

    await service.flush();
    await service.flush();
    expect(sentKeys, hasLength(1), reason: 'the pause has to hold against other triggers');
    expect((await outbox.pending()).single.attempts, 1, reason: 'and it must not inflate the count');
  });

  test('the pause is lifted by the channel coming back, and the retry then goes out', () async {
    failures['a'] = RepositoryException.connection;
    files = _FakeFiles();
    phase = _FakePhase(SessionPhase.live);
    service = OutboxService(outbox, messages, phase, files);
    service.start();
    await enqueue(['a']);

    await service.flush();
    expect(sentKeys, hasLength(1));

    failures.clear(); // the server is back
    phase.emit(SessionPhase.live); // a fresh live edge is a new reason to try
    for (var i = 0; i < 100 && sentKeys.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(sentKeys, hasLength(2));
    expect(sentKeys.first, sentKeys.last, reason: 'the retry must carry the SAME idempotency key');
    expect(await outbox.pending(), isEmpty);
  });

  test('a message the server keeps refusing retryably stops holding the queue', () async {
    // The spec's edge case: something that will never go must not occupy the
    // line forever. Set aside is not discarded — it stays, visible, retryable.
    failures['stuck'] = RepositoryException.internal; // the SERVER keeps refusing it
    service.start(); // a live edge lifts the backoff pause, which is what drives the retries
    final keys = await enqueue(['stuck', 'behind it']);

    for (var i = 0; i < 20 && (await outbox.pending()).isNotEmpty; i++) {
      phase.emit(SessionPhase.live);
      await service.flush();
    }

    final left = await outbox.watchQueue().first;
    expect(left.single.text, 'stuck');
    expect(left.single.status, OutboxStatus.error);
    expect(left.single.refusals, 10); // the ladder is spent by refusals, and only by them
    expect(sentKeys.where((k) => k == keys[0]), hasLength(10));
    // And the message behind it got out rather than waiting forever.
    expect(sentKeys, contains(keys[1]));
    expect(await outbox.pending(), isEmpty);
  });

  test('a flapping link never sets a message aside — a dead channel is not a refusal', () async {
    // The cap exists for a server that keeps saying no, not for a bad tunnel.
    // Counting connection failures would strand a perfectly good message within
    // seconds of a train going through one.
    failures['on my way'] = RepositoryException.connection;
    service.start();
    await enqueue(['on my way']);

    for (var i = 0; i < 25; i++) {
      phase.emit(SessionPhase.live); // each reconnect lifts the pause and buys an attempt
      await service.flush();
    }

    final entry = (await outbox.pending()).single;
    expect(entry.status, OutboxStatus.pending, reason: 'the network is not the message\'s fault');
    expect(entry.refusals, 0);
    expect(entry.attempts, greaterThan(10)); // it kept trying, as it must

    failures.clear();
    phase.emit(SessionPhase.live);
    await service.flush();
    expect(await outbox.pending(), isEmpty); // and it goes as soon as the link holds
  });

  test('a manual retry replenishes the ladder rather than being a single shot', () async {
    failures['stuck'] = RepositoryException.internal;
    service.start();
    final keys = await enqueue(['stuck']);
    for (var i = 0; i < 20 && (await outbox.pending()).isNotEmpty; i++) {
      phase.emit(SessionPhase.live);
      await service.flush();
    }
    expect((await outbox.watchQueue().first).single.status, OutboxStatus.error);
    final spent = sentKeys.length;

    // The user taps Retry. That has to mean "start over", not "one more try":
    // keeping the spent counters makes every later tap fail straight back.
    await outbox.markPending(clientMessageId: keys[0]);
    final requeued = (await outbox.pending()).single;
    expect(requeued.refusals, 0);
    expect(requeued.attempts, 0);

    for (var i = 0; i < 20 && (await outbox.pending()).isNotEmpty; i++) {
      phase.emit(SessionPhase.live);
      await service.flush();
    }
    expect(sentKeys.length - spent, 10, reason: 'a full ladder, not one attempt');
  });

  test('a pause dies with the entry that caused it — a discarded head does not hold the queue', () async {
    // The pause is keyed to one entry. A bare flag would keep every later
    // message waiting on a record that no longer exists.
    failures['head'] = RepositoryException.internal;
    final keys = await enqueue(['head']);
    await service.flush();
    expect((await outbox.pending()).single.attempts, 1); // paused now

    await outbox.remove(clientMessageId: keys[0]); // the user discards it
    final fresh = (await outbox.enqueue(chatId: 'c1', text: 'sent right after')).data!;
    await service.flush();

    expect(sentKeys, contains(fresh.clientMessageId), reason: 'a pause must not outlive its reason');
    expect(await outbox.pending(), isEmpty);
  });

  test('a discard landing mid-pass is honoured — the message is not sent', () async {
    // A pass spans as long as the sends ahead of an entry take. Anything the
    // user cancels in that window is gone from the store, and sending it anyway
    // publishes, permanently, a message they were shown had been cancelled.
    final keys = await enqueue(['first', 'second']);
    when(
      messages.sendMessage(
        chatId: anyNamed('chatId'),
        clientMessageId: anyNamed('clientMessageId'),
        text: anyNamed('text'),
        attachment: anyNamed('attachment'),
      ),
    ).thenAnswer((invocation) async {
      final key = invocation.namedArguments[#clientMessageId] as String;
      sentKeys.add(key);
      // While the first send is in flight, the user discards the second.
      if (key == keys[0]) await outbox.remove(clientMessageId: keys[1]);
      return RepositoryResult<MessageModel>.success(data: echo('c1', 'x'));
    });

    await service.flush();

    expect(sentKeys, [keys[0]]);
    expect(await outbox.pending(), isEmpty);
  });
}
