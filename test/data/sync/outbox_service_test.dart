import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/sync/outbox_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';
import 'package:nox_app/domain/model/chat/outbox_status.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
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
  late List<String> sentKeys;
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
    failures = <String, RepositoryException>{};
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
      sentKeys.add(key);
      final failure = failures[text];
      if (failure != null) return RepositoryResult<MessageModel>.error(exception: failure);
      return RepositoryResult<MessageModel>.success(data: echo(invocation.namedArguments[#chatId] as String, text ?? ''));
    });

    phase = _FakePhase(SessionPhase.live);
    service = OutboxService(outbox, messages, phase);
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
    service = OutboxService(outbox, messages, phase);
    await enqueue(['a']);

    await service.flush();

    expect(sentKeys, isEmpty);
    // No failed attempt was recorded, so the backoff does not grow for a reason
    // that has nothing to do with the message.
    expect((await outbox.pending()).single.attempts, 0);
  });

  test('catching up is not live: the drain waits for the replay to finish', () async {
    phase = _FakePhase(SessionPhase.catchingUp);
    service = OutboxService(outbox, messages, phase);
    await enqueue(['a']);

    await service.flush();

    expect(sentKeys, isEmpty);
  });

  test('the channel going live drains the queue with no one asking', () async {
    phase = _FakePhase(SessionPhase.disconnected);
    service = OutboxService(outbox, messages, phase);
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
    service = OutboxService(outbox, messages, phase);
    service.start();
    service.start();
    await enqueue(['once']);

    phase.emit(SessionPhase.live);
    for (var i = 0; i < 100 && sentKeys.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(sentKeys, hasLength(1));
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

  test('stop() waits for a pass in flight — logout must not wipe underneath a send', () async {
    await enqueue(['a']);
    final draining = service.flush();

    await service.stop();
    await draining;

    expect(await outbox.pending(), isEmpty);
  });
}
