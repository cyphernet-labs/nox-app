import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/remote/socket/socket_target_provider.dart';
import 'package:nox_app/data/remote/socket/socket_channel_factory.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:nox_tor/channel.dart';
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
  /// Connects a device that ALREADY belongs to this world: a stored cursor
  /// without a stored journal is the upgrade case, which tears the session down
  /// on purpose, so tests about replay have to say which world they are in.
  Future<FakeSocket> connect({int cursor = 0, String? label}) async {
    if (await sync.getCursor() > 0) await sync.setJournal('j_test');
    await client.start(
      url: url,
      credentialsProvider: () async => GreetingCredentials(label: label),
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

    test('a device whose first greeting found an empty journal asks for a replay from 0 next time', () async {
      // Read as "first" again, the second greeting adopted the head as its
      // starting point and skipped what had arrived in between - a message
      // from another device, lost until something happened to list the chat.
      await client.start(url: url, credentialsProvider: () async => const GreetingCredentials());
      final first = factory.latest;
      first.pushGreeting();
      await waitUntil(() => first.commandNamed('session.hello') != null, reason: 'the client greets');
      first.replyToHello(cursor: 0);
      await waitUntil(() async => await sync.hasCursor(), reason: 'the empty journal\'s cursor is stored');

      // The connection drops before anything was applied.
      await client.stop();
      await client.start(url: url, credentialsProvider: () async => const GreetingCredentials());
      final second = factory.latest;
      second.pushGreeting();
      await waitUntil(() => second.commandNamed('session.hello') != null, reason: 'the client greets again');

      expect((second.commandNamed('session.hello')!['data'] as Map<String, dynamic>)['since'], 0);
    });

    test('a device that has applied events asks for everything after its cursor', () async {
      await sync.advanceCursor(41);
      final socket = await connect(cursor: 99);

      expect((socket.commandNamed('session.hello')!['data'] as Map<String, dynamic>)['since'], 41);
      // There is history to receive, so the session is behind until it arrives.
      expect(client.currentPhase, SessionPhase.catchingUp);
    });

    test('an unpaired install holds the connection open instead of greeting', () async {
      // The window `pair` runs in. Greeting here would be refused - the
      // server does not know this device's key yet - and the refusal used to
      // be read as a revocation, which wiped the key and address mid-pairing
      // and bricked the install.
      await client.start(url: url, credentialsProvider: () async => const GreetingCredentials.unpaired());
      final socket = factory.latest;
      socket.pushGreeting();
      await settle();

      expect(socket.commandNamed('session.hello'), isNull, reason: 'nothing to greet with, so nothing is sent');
      expect(socket.closed, isFalse, reason: 'the connection is what pair needs');
    });

    test('a refused greeting tells the app, instead of retrying forever', () async {
      var rejected = false;
      client.onUnauthenticated = () => rejected = true;
      await client.start(url: url, credentialsProvider: () async => const GreetingCredentials());
      final socket = factory.latest;
      socket.pushGreeting();
      await waitUntil(() => socket.commandNamed('session.hello') != null);
      socket.reply(socket.sent.indexWhere((f) => f['cmd'] == 'session.hello'), ok: false, code: 'unauthenticated');
      await waitUntil(() => rejected, reason: 'the app has to learn it is no longer paired');

      // Not a reconnect loop: the peer will keep refusing, and whoever owns the
      // session decides what happens next.
      expect(client.currentPhase, SessionPhase.unsupported);
    });

    test('the greeting names nobody: the connection already proved the device (phase 044)', () async {
      final socket = await connect(cursor: 3);

      final data = socket.commandNamed('session.hello')!['data'] as Map<String, dynamic>;
      expect(data.keys, <String>['schema'], reason: 'a first greeting: no since either');
      expect(data.containsKey('device_key'), isFalse);
      expect(data.containsKey('signature'), isFalse);
      expect(data.containsKey('login_ref'), isFalse);
      expect(data.containsKey('label'), isFalse, reason: 'stated only after a rename');
    });

    test('a greeting that still carries a challenge is answered all the same, and the challenge ignored', () async {
      await client.start(url: url, credentialsProvider: () async => const GreetingCredentials());
      final socket = factory.latest;
      socket.pushRaw(
        jsonEncode({
          'srv': {'schema_max': 1, 'challenge': 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8='},
        }),
      );
      await waitUntil(() => socket.commandNamed('session.hello') != null, reason: 'the client greets back');
      expect((socket.commandNamed('session.hello')!['data'] as Map<String, dynamic>).containsKey('signature'), isFalse);
    });

    test('a changed journal id tears the session down instead of applying a stranger world', () async {
      var reported = 0;
      await client.start(url: url, credentialsProvider: () async => const GreetingCredentials(), onJournalChanged: () => reported++);
      final first = factory.latest;
      first.pushGreeting();
      await waitUntil(() => first.commandNamed('session.hello') != null, reason: 'the client greets');
      first.replyToHello(cursor: 5, journalId: 'j_one');
      await waitUntil(() async => await sync.getJournal() == 'j_one', reason: 'the first journal is persisted');

      // The server was rebuilt: same address, different world.
      await client.stop();
      await client.start(url: url, credentialsProvider: () async => const GreetingCredentials(), onJournalChanged: () => reported++);
      final second = factory.latest;
      second.pushGreeting();
      await waitUntil(() => second.commandNamed('session.hello') != null, reason: 'the client greets again');
      second.replyToHello(cursor: 2, journalId: 'j_two');

      await waitUntil(() => reported == 1, reason: 'the change is reported exactly once');
      expect(client.currentPhase, isNot(SessionPhase.live));
    });

    test('a greeting carrying no identity is not a success', () async {
      // Stage 1 always states who connected. Treating a reply without it as a
      // greeting would leave the PREVIOUS connection's person in place, and a
      // sign-in that timed out could then adopt a stranger.
      await client.start(url: url, credentialsProvider: () async => const GreetingCredentials());
      final socket = factory.latest;
      socket.pushGreeting();
      await waitUntil(() => socket.commandNamed('session.hello') != null, reason: 'the client greets');
      socket.reply(
        socket.sent.indexWhere((f) => f['cmd'] == 'session.hello'),
        data: {'schema': 1, 'cursor': 0, 'journal_id': 'j_test', 'limits': const <String, dynamic>{}},
      );

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(client.identity, isNull);
      expect(client.currentPhase, isNot(SessionPhase.live));
      expect(client.currentPhase, isNot(SessionPhase.catchingUp));
    });

    test('what the greeting declared dies with the connection that declared it', () async {
      final socket = await connect(cursor: 0, label: 'Anna');
      expect(client.identity, isNotNull);
      expect(client.limits, isNotNull);

      await socket.drop();
      await waitUntil(() => client.identity == null, reason: 'the identity is released on a drop');
      expect(client.limits, isNull);
      // The journal id is the deliberate exception: it names the world our
      // cache came from and outlives the socket by design.
      expect(client.journalId, isNotNull);
    });

    test('a cursor with no remembered journal is treated as a world change — the upgrade case', () async {
      // Every install from before this release is exactly this: it holds a
      // cursor learned from some world, and no journal record because the field
      // did not exist. Reading that as "no divergence" would opt the check out
      // of the one transition it was built for.
      await sync.advanceCursor(42);
      expect(await sync.getJournal(), isNull);

      var reported = 0;
      await client.start(url: url, credentialsProvider: () async => const GreetingCredentials(), onJournalChanged: () => reported++);
      final socket = factory.latest;
      socket.pushGreeting();
      await waitUntil(() => socket.commandNamed('session.hello') != null, reason: 'the client greets');
      socket.replyToHello(cursor: 1, journalId: 'j_rebuilt');

      await waitUntil(() => reported == 1, reason: 'an unremembered journal with a cursor is a change');
      await waitUntil(() async => await sync.getJournal() == 'j_rebuilt', reason: 'the new journal is recorded');
    });

    test('a FIRST-EVER connection adopts the journal without calling it a change', () async {
      // Nothing cached, nothing to discard: the empty world must not be
      // reported as stale or the app would wipe on every fresh install.
      var reported = 0;
      await client.start(url: url, credentialsProvider: () async => const GreetingCredentials(), onJournalChanged: () => reported++);
      final socket = factory.latest;
      socket.pushGreeting();
      await waitUntil(() => socket.commandNamed('session.hello') != null, reason: 'the client greets');
      socket.replyToHello(cursor: 3, journalId: 'j_first');

      await waitUntil(() async => await sync.getJournal() == 'j_first', reason: 'the journal is adopted');
      expect(reported, 0);
    });

    test('a provider that cannot tell who we are defers the greeting instead of claiming nobody', () async {
      await client.start(url: url, credentialsProvider: () async => null);
      final socket = factory.latest;
      socket.pushGreeting();
      // Greeting anonymously would take a throw-away identity and write rows
      // under it, so nothing is sent at all.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(socket.commandNamed('session.hello'), isNull);
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
      await client.start(url: url, credentialsProvider: () async => const GreetingCredentials(), onJournalChanged: () => reported++);
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
        credentialsProvider: () async => const GreetingCredentials(),
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
        credentialsProvider: () async => const GreetingCredentials(),
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

    test('a replay that overtakes the greeting reply still ends the catch-up', () async {
      // The reply and the replay can land in one burst - through Tor bytes
      // come in cells - and be delivered before the code awaiting the reply
      // resumes. The catch-up rule must still see them, or the socket sits in
      // catchingUp until the next live event and the outgoing queue waits.
      await sync.setJournal('j_test');
      await sync.advanceCursor(4);
      await client.start(url: url, credentialsProvider: () async => const GreetingCredentials());
      final socket = factory.latest;
      socket.pushGreeting();
      await waitUntil(() => socket.commandNamed('session.hello') != null, reason: 'the client greets back');

      socket.replyToHello(cursor: 6);
      socket.pushEvent(seq: 5);
      socket.pushEvent(seq: 6);

      await waitUntil(() => client.currentPhase == SessionPhase.live, reason: 'caught up from the burst');
    });

    test('a greeting held up past its connection is dropped, never sent on the next one', () async {
      // Signed over the first connection's challenge, a hello sent on the
      // second reads as a forged one: the server answers `unauthenticated`,
      // and that is the forced logout that wipes the device.
      var gate = Completer<GreetingCredentials?>();
      var asked = 0;
      await client.start(
        url: url,
        credentialsProvider: () {
          asked++;
          return gate.future;
        },
      );
      await waitUntil(() => factory.created.isNotEmpty, reason: 'dialled');
      final first = factory.latest;
      first.pushGreeting();
      await waitUntil(() => asked == 1, reason: 'the greeting reads who we are');

      await first.drop();
      await waitUntil(() => factory.created.length == 2, reason: 'the ladder dials again');
      final second = factory.latest;
      gate.complete(const GreetingCredentials());
      await settle();

      expect(first.commandNamed('session.hello'), isNull);
      expect(second.commandNamed('session.hello'), isNull, reason: 'the old greeting stays with its connection');
      expect(second.closed, isFalse, reason: 'and does not tear the new one down');

      gate = Completer<GreetingCredentials?>()..complete(const GreetingCredentials());
      second.pushGreeting();
      await waitUntil(() => second.commandNamed('session.hello') != null, reason: 'the new connection greets for itself');
      second.replyToHello(cursor: 0);
      await waitUntil(() => client.currentPhase == SessionPhase.live, reason: 'greeted');
      expect(second.sent.where((f) => f['cmd'] == 'session.hello'), hasLength(1));
    });

    test('a reconnect under an unanswered greeting leaves the new connection alone', () async {
      await client.start(url: url, credentialsProvider: () async => const GreetingCredentials());
      await waitUntil(() => factory.created.isNotEmpty, reason: 'dialled');
      final first = factory.latest;
      first.pushGreeting();
      await waitUntil(() => first.commandNamed('session.hello') != null, reason: 'the hello is out');

      await client.reconnect();
      final second = factory.latest;
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      expect(factory.created, hasLength(2), reason: 'the failed hello schedules no dial of its own');
      expect(second.closed, isFalse);
      expect(client.currentPhase, SessionPhase.connecting, reason: 'the new attempt is still the one in progress');
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

  // A server from phase 039 adds `addresses` to the greeting reply and sends a
  // `server.addresses` event (seq 0). Since phase 040 the app reads both: the
  // greeting's list is kept with the connection, and its presence is the
  // support flag for `device.setAccessKey` (contract §2.1, §3, §8A).
  group('a server from phase 039', () {
    Future<FakeSocket> greetedWith(Map<String, dynamic>? addresses) async {
      await client.start(
        url: url,
        credentialsProvider: () async => const GreetingCredentials(label: 'Anna'),
      );
      final socket = factory.latest;
      socket.pushGreeting();
      await waitUntil(() => socket.commandNamed('session.hello') != null, reason: 'the client greets back');
      socket.reply(
        socket.sent.indexWhere((f) => f['cmd'] == 'session.hello'),
        data: {
          'schema': 1,
          'cursor': 3,
          'journal_id': 'j_test',
          'limits': {'max_message_bytes': 65536, 'max_attachment_bytes': 104857600, 'max_frame_bytes': 131072},
          'identity': {'id': 'u_1', 'label': 'Anna'},
          'addresses': ?addresses,
        },
      );
      await waitUntil(
        () => client.currentPhase == SessionPhase.live || client.currentPhase == SessionPhase.catchingUp,
        reason: 'the greeting reply is applied',
      );
      return socket;
    }

    test('the greeting says where the server is, and that it reads access keys', () async {
      await greetedWith({
        'direct': ['192.168.1.20:8080', '[fd12:3456::20]:8080'],
        'onion': '${'a' * 56}.onion:443',
      });

      expect(client.identity?.label, 'Anna');
      expect(client.addresses?.direct, ['192.168.1.20:8080', '[fd12:3456::20]:8080']);
      expect(client.addresses?.onion, '${'a' * 56}.onion:443');
      expect(client.supportsAccessKeys, isTrue);
    });

    test('a server older than 039 states nothing, and is not asked to register a key', () async {
      await greetedWith(null);

      expect(client.addresses, isNull);
      expect(client.supportsAccessKeys, isFalse);
    });

    test('an empty list is still the support flag: the server says it has no direct address', () async {
      await greetedWith({'direct': <String>[]});

      expect(client.addresses?.direct, isEmpty);
      expect(client.addresses?.onion, isNull);
      expect(client.supportsAccessKeys, isTrue);
    });

    test('what the greeting said about addresses dies with its connection', () async {
      final socket = await greetedWith({
        'direct': ['192.168.1.20:8080'],
      });
      await socket.drop();
      await waitUntil(() => client.addresses == null, reason: 'the teardown forgets it');
      expect(client.supportsAccessKeys, isFalse);
    });

    test('the server.addresses event leaves the session as it was', () async {
      final socket = await connect(cursor: 0);
      final seen = <String>[];
      final sub = client.events.listen((e) => seen.add(e.event));

      socket.pushEvent(
        seq: 0,
        event: 'server.addresses',
        data: {
          'direct': ['192.168.1.21:8080'],
        },
      );
      socket.pushEvent(seq: 1);
      await settle();
      await sub.cancel();

      expect(client.currentPhase, SessionPhase.live);
      expect(seen, ['server.addresses', 'message.new']);
    });
  });

  group('the path choice is bounded (phase 042)', () {
    test('a choice that never ends is abandoned, and the next attempt dials what the next choice says', () async {
      final hung = Completer<Uri?>();
      final targets = ScriptedTargets.gated(hung, then: [Uri.parse('wss://10.0.0.1:9000/ws')]);
      client = NoxSocketClient.forTest(factory, sync, pathChoiceBudget: const Duration(milliseconds: 100));
      await client.start(targets: targets, credentialsProvider: () async => const GreetingCredentials());

      await waitUntil(() => targets.asked == 2, reason: 'asked again after the bound and the first rung');
      await waitUntil(() => factory.created.length == 1, reason: 'the second answer is dialled');
      final socket = factory.latest;
      socket.pushGreeting();
      await waitUntil(() => socket.commandNamed('session.hello') != null, reason: 'the client greets back');
      socket.replyToHello(cursor: 0);
      await waitUntil(() => client.currentPhase == SessionPhase.live, reason: 'greeted');

      // The first choice answers at last - too late to count for anything.
      hung.complete(Uri.parse('wss://10.0.0.9:9000/ws'));
      await settle();

      expect(factory.urls, [Uri.parse('wss://10.0.0.1:9000/ws')]);
      expect(client.currentPhase, SessionPhase.live);
    });

    test('a restart during a hung choice asks again at once, without waiting for the bound', () async {
      final hung = Completer<Uri?>();
      final targets = ScriptedTargets.gated(hung, then: [Uri.parse('wss://10.0.0.1:9000/ws')]);
      client = NoxSocketClient.forTest(factory, sync, pathChoiceBudget: const Duration(minutes: 2));
      await client.start(targets: targets);
      await waitUntil(() => targets.asked == 1, reason: 'the first choice is under way');

      // How the channel restarts: Try again on No connection.
      await client.stop();
      await client.start(targets: targets);

      await waitUntil(() => factory.created.length == 1, reason: 'dialled at once, not two minutes later');
      expect(targets.asked, 2);
      hung.complete(null);
    });

    test('the ladder never stops on its own, and its pause has a ceiling', () async {
      final targets = ScriptedTargets([null]);
      client = NoxSocketClient.forTest(
        factory,
        sync,
        minBackoff: const Duration(milliseconds: 2),
        maxBackoff: const Duration(milliseconds: 20),
      );
      await client.start(targets: targets);

      // Two dozen failed rounds in well under the two seconds waitUntil gives:
      // only a ceiling on the pause makes that possible.
      await waitUntil(() => targets.asked >= 25, reason: 'still asking after many failed rounds');
    });
  });

  group('the target provider (phase 040)', () {
    test('it is asked before every attempt, and the socket dials what it says', () async {
      final targets = ScriptedTargets([Uri.parse('wss://10.0.0.1:9000/ws'), Uri.parse('wss://10.0.0.2:9000/ws')]);
      await client.start(targets: targets);
      expect(factory.urls, [Uri.parse('wss://10.0.0.1:9000/ws')]);

      await factory.latest.drop();
      await waitUntil(() => factory.urls.length == 2, reason: 'the ladder asks again');

      expect(factory.urls.last, Uri.parse('wss://10.0.0.2:9000/ws'));
      expect(targets.asked, 2);
    });

    test('no path means waiting on the ladder, and asking again', () async {
      final targets = ScriptedTargets([null, Uri.parse('wss://10.0.0.1:9000/ws')]);
      await client.start(targets: targets);

      expect(factory.created, isEmpty, reason: 'nothing to dial');
      await waitUntil(() => client.currentPhase == SessionPhase.disconnected, reason: 'on the ladder');
      await waitUntil(() => factory.created.length == 1, reason: 'asked again after the first rung');
      expect(targets.asked, 2);
    });

    test('a greeting is reported against the address it came over', () async {
      final targets = ScriptedTargets([Uri.parse('wss://10.0.0.1:9000/ws')]);
      await client.start(targets: targets, credentialsProvider: () async => const GreetingCredentials());
      final socket = factory.latest;
      socket.pushGreeting();
      await waitUntil(() => socket.commandNamed('session.hello') != null, reason: 'the client greets back');
      socket.replyToHello(cursor: 0);
      await waitUntil(() => targets.greeted.isNotEmpty, reason: 'the greeting is reported');

      expect(targets.greeted, [Uri.parse('wss://10.0.0.1:9000/ws')]);
      expect(client.currentUrl, Uri.parse('wss://10.0.0.1:9000/ws'));
    });

    test('another key at a direct address is reported and the next path is tried, with nothing shown (FR-011)', () async {
      final targets = ScriptedTargets([Uri.parse('wss://192.168.1.20:8080/ws'), Uri.parse('wss://${'a' * 56}.onion/ws')]);
      await client.start(targets: targets);

      factory.latest.refuseServerKey();
      await waitUntil(() => factory.created.length == 2, reason: 'the ladder goes on');

      expect(targets.refused, [Uri.parse('wss://192.168.1.20:8080/ws')]);
      expect(client.currentPhase, isNot(SessionPhase.serverMismatch));
    });

    test('another key behind the onion address is the wrong server, terminal (FR-011)', () async {
      final targets = ScriptedTargets([Uri.parse('wss://${'a' * 56}.onion/ws'), Uri.parse('wss://10.0.0.1:9000/ws')]);
      await client.start(targets: targets);

      factory.latest.refuseServerKey();
      await settle();

      expect(client.currentPhase, SessionPhase.serverMismatch);
      expect(targets.refused, isEmpty, reason: 'not reported as "not home"');
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(factory.created, hasLength(1), reason: 'nothing retries a refusal on its own');
    });

    for (final failure in [
      ChannelFailure.network,
      ChannelFailure.timeout,
      ChannelFailure.tls,
      ChannelFailure.protocol,
      ChannelFailure.torOnionUnreachable,
    ]) {
      test('a ${failure.name} failure of the channel is a failed attempt on the ladder - at any address, and never a logout', () async {
        var rejected = false;
        client.onUnauthenticated = () => rejected = true;
        final targets = ScriptedTargets([Uri.parse('wss://${'a' * 56}.onion/ws'), Uri.parse('wss://10.0.0.1:9000/ws')]);
        await client.start(targets: targets);

        factory.latest.refuseChannel(failure);
        await waitUntil(() => factory.created.length == 2, reason: 'the ladder goes on');

        expect(client.currentPhase, isNot(SessionPhase.serverMismatch));
        expect(client.currentPhase, isNot(SessionPhase.unsupported));
        expect(targets.refused, isEmpty, reason: 'only another key means "not home"');
        expect(rejected, isFalse);
      });
    }

    test('a wrong server at the onion address never logs anybody out (FR-012)', () async {
      var rejected = false;
      client.onUnauthenticated = () => rejected = true;
      await client.start(targets: ScriptedTargets([Uri.parse('wss://${'a' * 56}.onion/ws')]));

      factory.latest.refuseServerKey();
      await waitUntil(() => client.currentPhase == SessionPhase.serverMismatch, reason: 'the banner, not a wipe');
      expect(rejected, isFalse);
    });

    test('a pairing never completes over connections whose server key was refused (SC-003)', () async {
      // Every machine dialled proves another key. The connection holds what it
      // is given until the channel is verified, and a refused one never is -
      // see socket_channel_factory_test for the hold itself.
      factory.refuseEvery = ChannelFailure.wrongServer;
      await client.start(
        targets: ScriptedTargets([Uri.parse('wss://192.168.1.20:8080/ws')]),
        credentialsProvider: () async => const GreetingCredentials.unpaired(),
      );
      await waitUntil(() => factory.created.isNotEmpty, reason: 'dialled');
      final stranger = factory.latest;
      stranger.refuseServerKey();
      await expectLater(client.pair(token: 't', platform: 'macos'), throwsA(isA<SocketUnavailableException>()));
      for (final socket in factory.created) {
        expect(socket.commandNamed('pair'), isNull, reason: 'every connection dialled refused the key');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('a stop while the path is being chosen dials nothing afterwards', () async {
      final gate = Completer<Uri?>();
      final targets = ScriptedTargets.gated(gate);
      final starting = client.start(targets: targets);
      await settle();
      await client.stop();
      gate.complete(Uri.parse('wss://10.0.0.1:9000/ws'));
      await starting;
      await settle();

      expect(factory.created, isEmpty);
    });

    test('reconnect drops the connection and asks for a target at once', () async {
      final targets = ScriptedTargets([Uri.parse('wss://${'a' * 56}.onion/ws'), Uri.parse('wss://10.0.0.1:9000/ws')]);
      await client.start(targets: targets);
      final first = factory.latest;

      await client.reconnect();

      expect(first.closed, isTrue);
      expect(factory.urls.last, Uri.parse('wss://10.0.0.1:9000/ws'));
    });

    test('a command sent while the slow path comes up waits past the short timeout (FR-023)', () async {
      final gate = Completer<Uri?>();
      final targets = ScriptedTargets.gated(gate)..slow = true;
      unawaited(client.start(targets: targets, credentialsProvider: () async => const GreetingCredentials()));
      await settle();

      final pending = client.send('chats.list', {'page': 1});
      var failed = false;
      unawaited(pending.then((_) {}, onError: (Object _) => failed = true));
      // Longer than a command may otherwise wait for its greeting.
      await Future<void>.delayed(NoxSocketClient.sendTimeout + const Duration(milliseconds: 500));
      expect(failed, isFalse, reason: 'still waiting for the path');

      targets.slow = false;
      gate.complete(Uri.parse('wss://10.0.0.1:9000/ws'));
      await waitUntil(() => factory.created.isNotEmpty, reason: 'the path arrived');
      final socket = factory.latest;
      socket.pushGreeting();
      await waitUntil(() => socket.commandNamed('session.hello') != null, reason: 'the client greets back');
      socket.replyToHello(cursor: 0);
      await waitUntil(() => socket.commandNamed('chats.list') != null, reason: 'the command goes out after the greeting');
      socket.reply(socket.sent.indexWhere((f) => f['cmd'] == 'chats.list'), data: {'chats': const [], 'has_more': false});
      expect((await pending).ok, isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('a read with a cache behind it does not wait for the slow path, it fails at once', () async {
      // The other side of FR-023: a list read waiting up to the slow budget kept
      // the chats and messages already on the device off the screen for as long
      // as Tor took. Its caller serves the cache and reads again once live.
      final gate = Completer<Uri?>();
      final targets = ScriptedTargets.gated(gate)..slow = true;
      unawaited(client.start(targets: targets, credentialsProvider: () async => const GreetingCredentials()));
      await settle();

      final read = client.send('chats.list', {'page': 1}, waitForConnection: false).timeout(const Duration(milliseconds: 200));

      await expectLater(read, throwsA(isA<SocketUnavailableException>()));
      gate.complete(null);
    });

    test('a read with a cache behind it goes out as usual once the greeting is done', () async {
      final socket = await connect();

      final read = client.send('chats.list', {'page': 1}, waitForConnection: false);
      await waitUntil(() => socket.commandNamed('chats.list') != null, reason: 'the read goes out');
      socket.reply(socket.sent.indexWhere((f) => f['cmd'] == 'chats.list'), data: {'chats': const [], 'has_more': false});

      expect((await read).ok, isTrue);
    });

    test('pairing waits for the connection while the path is still being chosen', () async {
      // A started socket can be between connections when pairing is asked
      // for: choosing a path, or a restart that superseded the attempt the
      // caller was counting on. Failing at once there told the person their
      // pairing did not work while the channel was a moment from opening.
      final gate = Completer<Uri?>();
      unawaited(client.start(targets: ScriptedTargets.gated(gate), credentialsProvider: () async => const GreetingCredentials.unpaired()));
      await settle();

      final pairing = client.pair(token: 't', platform: 'macos');
      var failed = false;
      unawaited(pairing.then((_) {}, onError: (Object _) => failed = true));
      await settle();
      expect(failed, isFalse, reason: 'waiting for the channel, not refused');

      gate.complete(Uri.parse('wss://10.0.0.1:9000/ws'));
      await waitUntil(() => factory.created.isNotEmpty && factory.latest.commandNamed('pair') != null, reason: 'sent once open');
      factory.latest.reply(
        factory.latest.sent.indexWhere((f) => f['cmd'] == 'pair'),
        data: {
          'identity': {'id': 'u_me', 'label': 'Anna', 'created': true},
        },
      );
      expect((await pairing).ok, isTrue);
    });

    test('pairing with no channel coming gives up after the short wait', () async {
      await client.start(targets: ScriptedTargets(const [null]), credentialsProvider: () async => const GreetingCredentials.unpaired());

      await expectLater(client.pair(token: 't', platform: 'macos'), throwsA(isA<SocketUnavailableException>()));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('a pairing whose connection went away is presented again on the next', () async {
      // Through Tor one dial can run out its time while the next gets through,
      // and a network change tears the connection down. The server answers the
      // same token from the same device with the same identity (contract §8A),
      // so presenting it again is safe whatever became of the first.
      await client.start(
        targets: ScriptedTargets([Uri.parse('wss://10.0.0.1:9000/ws'), Uri.parse('wss://10.0.0.2:9000/ws')]),
        credentialsProvider: () async => const GreetingCredentials.unpaired(),
      );
      await waitUntil(() => factory.created.isNotEmpty, reason: 'dialled');
      final first = factory.latest;
      final pairing = client.pair(token: 't', platform: 'macos');
      await waitUntil(() => first.commandNamed('pair') != null, reason: 'handed to the first');

      await first.drop();
      await waitUntil(() => factory.created.length == 2, reason: 'the ladder dials again');
      final second = factory.latest;
      await waitUntil(() => second.commandNamed('pair') != null, reason: 'presented again');
      second.reply(
        second.sent.indexWhere((f) => f['cmd'] == 'pair'),
        data: {
          'identity': {'id': 'u_me', 'label': 'Anna', 'created': true},
        },
      );

      expect((await pairing).ok, isTrue);
    });

    test('a pairing keeps one budget across the connections it takes', () async {
      // Each presentation used to start a fresh wait, so a pairing could run
      // to twice its budget - three times on the slow path - with the person
      // watching a spinner.
      await client.start(
        targets: ScriptedTargets([Uri.parse('wss://10.0.0.1:9000/ws'), Uri.parse('wss://10.0.0.2:9000/ws')]),
        credentialsProvider: () async => const GreetingCredentials.unpaired(),
      );
      await waitUntil(() => factory.created.isNotEmpty, reason: 'dialled');
      final first = factory.latest;
      final waited = Stopwatch()..start();
      final pairing = client.pair(token: 't', platform: 'macos');
      await Future<void>.delayed(NoxSocketClient.sendTimeout - const Duration(milliseconds: 500));

      // Gone just before the budget runs out; the next connection never answers.
      await first.drop();

      await expectLater(pairing, throwsA(isA<SocketUnavailableException>()));
      expect(waited.elapsed, lessThan(NoxSocketClient.sendTimeout + const Duration(seconds: 2)));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('pairing carries the token, the platform and the public half of the access key - and no device key', () async {
      await client.start(url: url, credentialsProvider: () async => const GreetingCredentials.unpaired());
      final socket = factory.latest;
      unawaited(client.pair(token: 't', platform: 'macos', accessKey: 'QUJD').then((_) {}, onError: (Object _) {}));
      await waitUntil(() => socket.commandNamed('pair') != null, reason: 'pair is sent');

      final data = socket.commandNamed('pair')!['data'] as Map<String, dynamic>;
      expect(data['access_key'], 'QUJD');
      expect(data['token'], 't');
      expect(data['platform'], 'macos');
      expect(data.containsKey('device_key'), isFalse, reason: 'the server takes it from the connection (phase 044)');
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

/// Hands out addresses from a script, one per attempt, and records what the
/// socket reports back.
class ScriptedTargets implements SocketTargetProvider {
  ScriptedTargets(List<Uri?> script) : _script = List<Uri?>.of(script), _gate = null;

  /// Holds the first answer until [gate] completes; later calls follow [then].
  ScriptedTargets.gated(Completer<Uri?> gate, {List<Uri?> then = const <Uri?>[]}) : _script = List<Uri?>.of(then), _gate = gate;

  final List<Uri?> _script;
  final Completer<Uri?>? _gate;
  int asked = 0;
  bool slow = false;
  final List<Uri> greeted = <Uri>[];
  final List<Uri> refused = <Uri>[];

  @override
  Future<Uri?> nextTarget() async {
    asked++;
    final gate = _gate;
    if (gate != null && asked == 1) return gate.future;
    if (_script.isEmpty) return null;
    return _script.length == 1 ? _script.first : _script.removeAt(0);
  }

  @override
  bool get bringingUpSlowPath => slow;

  @override
  void reportGreeted(Uri url) => greeted.add(url);

  @override
  void reportWrongServer(Uri url) => refused.add(url);
}
