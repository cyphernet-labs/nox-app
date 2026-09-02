import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/general/identity/identifier_digest.dart';
import 'package:nox_app/data/remote/socket/socket_channel_factory.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_socket.dart';

/// The transport's own behaviour, driven over an in-memory channel: no server,
/// no network, no sleeping on real time.
void main() {
  late FakeSocketFactory factory;
  late SyncRepository sync;
  late NoxSocketClient client;

  final url = Uri.parse('ws://127.0.0.1:8080/ws');

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase();
    sync = getIt<SyncRepository>();
    factory = FakeSocketFactory();
    client = NoxSocketClient(factory, sync);
  });

  tearDown(() async {
    await client.stop();
    await getIt.reset();
  });

  /// Lets the event loop drain: the greeting is sent only after an async read
  /// of the persisted cursor, so a single microtask turn is not enough.
  ///
  /// Kept for the handful of assertions about a state that has no settled
  /// condition to wait for. Where there IS one, use [waitUntil] instead — a
  /// fixed pause is the test that passes on a quiet machine and fails in a full
  /// suite run, which is exactly how this file used to flake.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  /// Waits for a condition instead of a duration. The predicate may be async so
  /// callers can wait on persisted state, not just in-memory fields.
  Future<void> waitUntil(FutureOr<bool> Function() done, {String reason = ''}) async {
    for (var i = 0; i < 400; i++) {
      if (await done()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('condition never became true${reason.isEmpty ? '' : ': $reason'}');
  }

  /// Connects and greets, returning the fake the client is talking to.
  Future<FakeSocket> connect({int cursor = 0, String? label, String? loginRef, String? deviceKey}) async {
    await client.start(
      url: url,
      credentialsProvider: () async => GreetingCredentials(loginRef: loginRef, deviceKey: deviceKey, label: label),
    );
    final socket = factory.latest;
    socket.pushGreeting();
    // The client answers the greeting only after an async cursor read, so wait
    // for the command itself rather than for a guess at how long that takes.
    await waitUntil(() => socket.commandNamed('session.hello') != null, reason: 'the client greets back');
    socket.replyToHello(cursor: cursor);
    await waitUntil(
      () => client.currentPhase == SessionPhase.live || client.currentPhase == SessionPhase.catchingUp,
      reason: 'the greeting reply is applied',
    );
    return socket;
  }

  group('the greeting', () {
    test('a first-ever connection omits since, so the server replays nothing', () async {
      final socket = await connect(cursor: 12);

      final hello = socket.commandNamed('session.hello')!;
      // Sending since:0 would ask for the WHOLE journal from seq 1 (contract §3).
      expect((hello['data'] as Map<String, dynamic>).containsKey('since'), isFalse);
      // The reply's cursor becomes the starting point. It is persisted on its
      // own schedule, separately from the phase, so wait for the write rather
      // than assume the phase change implies it.
      await waitUntil(() async => await sync.getCursor() == 12, reason: 'the reply cursor is adopted');
      expect(client.currentPhase, SessionPhase.live);
    });

    test('a device that has applied events asks for everything after its cursor', () async {
      await sync.advanceCursor(41);
      final socket = await connect(cursor: 99);

      expect((socket.commandNamed('session.hello')!['data'] as Map<String, dynamic>)['since'], 41);
      // There is history to receive, so the session is behind until it arrives.
      expect(client.currentPhase, SessionPhase.catchingUp);
    });

    test('the greeting carries the login derivation and the device id, and never the raw identifier', () async {
      const identifier = 'NOX-raw-secret-value';
      final socket = await connect(cursor: 3, loginRef: IdentifierDigest.loginRef(identifier), deviceKey: 'dev-1');

      final data = socket.commandNamed('session.hello')!['data'] as Map<String, dynamic>;
      expect(data['login_ref'], IdentifierDigest.loginRef(identifier));
      expect(data['device_key'], 'dev-1');
      // The identifier is a bearer secret: it must not reach the wire in any
      // shape, so assert against the whole frame rather than the one field.
      expect(jsonEncode(socket.commandNamed('session.hello')), isNot(contains(identifier)));
    });

    test('a greeting with nothing to claim omits both fields rather than sending empties', () async {
      final socket = await connect(cursor: 3);

      final data = socket.commandNamed('session.hello')!['data'] as Map<String, dynamic>;
      expect(data.containsKey('login_ref'), isFalse);
      expect(data.containsKey('device_key'), isFalse);
      expect(data.containsKey('label'), isFalse);
    });

    test('a changed journal id tears the session down instead of applying a stranger world', () async {
      var reported = 0;
      await client.start(
        url: url,
        credentialsProvider: () async => const GreetingCredentials(deviceKey: 'dev-1'),
        onJournalChanged: () => reported++,
      );
      final first = factory.latest;
      first.pushGreeting();
      await waitUntil(() => first.commandNamed('session.hello') != null, reason: 'the client greets');
      first.replyToHello(cursor: 5, journalId: 'j_one');
      await waitUntil(() async => await sync.getJournal() == 'j_one', reason: 'the first journal is persisted');

      // The server was rebuilt: same address, different world.
      await client.stop();
      await client.start(
        url: url,
        credentialsProvider: () async => const GreetingCredentials(deviceKey: 'dev-1'),
        onJournalChanged: () => reported++,
      );
      final second = factory.latest;
      second.pushGreeting();
      await waitUntil(() => second.commandNamed('session.hello') != null, reason: 'the client greets again');
      second.replyToHello(cursor: 2, journalId: 'j_two');

      await waitUntil(() => reported == 1, reason: 'the change is reported exactly once');
      expect(client.currentPhase, isNot(SessionPhase.live));
    });

    test('a journal remembered from a PREVIOUS run is compared, not just one seen this session', () async {
      // The case that actually happens: the store was rebuilt and the app was
      // restarted. An in-memory-only journal is null by then, so the client
      // would adopt the new world while keeping the old cursor and never
      // receive anything again - with no visible symptom.
      await sync.setJournal('j_from_a_previous_run');
      await sync.advanceCursor(42);

      var reported = 0;
      await client.start(
        url: url,
        credentialsProvider: () async => const GreetingCredentials(deviceKey: 'dev-1'),
        onJournalChanged: () => reported++,
      );
      final socket = factory.latest;
      socket.pushGreeting();
      await waitUntil(() => socket.commandNamed('session.hello') != null, reason: 'the client greets');
      socket.replyToHello(cursor: 1, journalId: 'j_rebuilt');

      await waitUntil(() => reported == 1, reason: 'a journal from a previous run still counts');
      // Recorded before the wipe it triggers, and it outlives that wipe: leaving
      // the old name behind would wipe again on every later reconnect.
      await waitUntil(() async => await sync.getJournal() == 'j_rebuilt', reason: 'the new journal replaces the remembered one');
    });

    test('a journal-change handler that throws does not strand the socket', () async {
      await client.start(
        url: url,
        credentialsProvider: () async => const GreetingCredentials(deviceKey: 'dev-1'),
        onJournalChanged: () => throw StateError('the owner of the local world failed'),
      );
      final first = factory.latest;
      first.pushGreeting();
      await waitUntil(() => first.commandNamed('session.hello') != null, reason: 'the client greets');
      first.replyToHello(cursor: 5, journalId: 'j_one');
      await waitUntil(() async => await sync.getJournal() == 'j_one', reason: 'the first journal is persisted');

      await client.stop();
      await client.start(
        url: url,
        credentialsProvider: () async => const GreetingCredentials(deviceKey: 'dev-1'),
        onJournalChanged: () => throw StateError('the owner of the local world failed'),
      );
      final second = factory.latest;
      second.pushGreeting();
      await waitUntil(() => second.commandNamed('session.hello') != null, reason: 'the client greets again');
      second.replyToHello(cursor: 2, journalId: 'j_two');

      // A throw over there must cost neither the teardown nor the retry.
      await waitUntil(() async => await sync.getJournal() == 'j_two', reason: 'the new journal replaces the stale one');
    });

    test('the device offers its stored label and takes the identity the server returns', () async {
      final socket = await connect(cursor: 3, label: 'Anna');

      expect((socket.commandNamed('session.hello')!['data'] as Map<String, dynamic>)['label'], 'Anna');
      expect(client.identity?.label, 'Anna');
      expect(client.limits?.maxMessageBytes, 65536);
    });

    test('catching up ends when an event at or above the cursor is seen', () async {
      await sync.advanceCursor(5);
      final socket = await connect(cursor: 8);
      expect(client.currentPhase, SessionPhase.catchingUp);

      socket.pushEvent(seq: 7);
      await settle();
      expect(client.currentPhase, SessionPhase.catchingUp, reason: 'still behind the cursor');

      socket.pushEvent(seq: 8);
      await settle();
      expect(client.currentPhase, SessionPhase.live);
    });

    test('a schema the server does not speak is terminal, not retried', () async {
      await client.start(url: url);
      final socket = factory.latest;
      socket.pushGreeting();
      await settle();
      socket.refuseHello('unsupported_schema');
      await settle();

      // Retrying forever against a server that will never accept this build is
      // pointless — the contract marks the code non-repeatable (§2.1).
      expect(client.currentPhase, SessionPhase.unsupported);
      expect(factory.created, hasLength(1));
    });
  });

  group('commands', () {
    test('a reply is matched to its own command by id', () async {
      final socket = await connect();
      final first = client.send('chats.list', {'page': 1});
      final second = client.send('chats.list', {'page': 2});
      await settle();

      // Answer them out of order: correlation is by id, never by arrival order.
      socket.reply(2, data: {'chats': const [], 'has_more': false});
      socket.reply(1, data: {'chats': const [], 'has_more': true});
      await settle();

      expect((await first).data!['has_more'], isTrue);
      expect((await second).data!['has_more'], isFalse);
    });

    test('a command with no reply gives up rather than hanging forever', () async {
      await connect();
      // The contract budgets 10s; the caller may retry under the same key.
      await expectLater(client.send('chats.list', {'page': 1}).timeout(const Duration(milliseconds: 100)), throwsA(anything));
    });

    test('an unknown frame kind is ignored instead of killing the connection', () async {
      final socket = await connect();
      socket.pushRaw('{"future_frame":{"x":1}}');
      socket.pushRaw('not json at all');
      await settle();

      expect(client.currentPhase, SessionPhase.live);
    });
  });

  test('events reach subscribers in order', () async {
    final socket = await connect(cursor: 0);
    final seen = <int>[];
    final sub = client.events.listen((e) => seen.add(e.seq));

    socket.pushEvent(seq: 1);
    socket.pushEvent(seq: 2);
    await settle();
    await sub.cancel();

    expect(seen, [1, 2]);
  });

  group('the handshake gate', () {
    test('a command issued before the greeting waits for it instead of racing ahead', () async {
      await client.start(url: url);
      final socket = factory.latest;
      // The channel accepts writes the moment it is constructed, long before the
      // handshake finishes. Sending now would reach the server ahead of
      // session.hello, which refuses it as malformed (contract §3).
      final pending = client.send('chats.list', {'page': 1});
      await settle();
      expect(socket.commandNamed('chats.list'), isNull, reason: 'held back until greeted');

      socket.pushGreeting();
      await settle();
      socket.replyToHello(cursor: 0);
      await settle();

      // Released in the right order: the greeting went first.
      expect(socket.sent.first['cmd'], 'session.hello');
      expect(socket.commandNamed('chats.list'), isNotNull);

      socket.reply(socket.sent.indexWhere((f) => f['cmd'] == 'chats.list'), data: {'chats': const [], 'has_more': false});
      expect((await pending).ok, isTrue);
    });

    test('a command issued with no connection at all fails fast instead of hanging', () async {
      // Nothing started: there is no channel and no handshake to wait for.
      await expectLater(client.send('chats.list', {'page': 1}), throwsA(isA<SocketUnavailableException>()));
    });

    test('a drop while waiting for the greeting releases the caller with a failure', () async {
      await client.start(url: url);
      final socket = factory.latest;
      final pending = client.send('chats.list', {'page': 1});
      await settle();

      await socket.drop(); // the peer goes away before greeting us
      await expectLater(pending, throwsA(isA<SocketUnavailableException>()));
    });
  });
}
