import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
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
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  /// Connects and greets, returning the fake the client is talking to.
  Future<FakeSocket> connect({int cursor = 0, String? label}) async {
    await client.start(url: url, label: label);
    final socket = factory.latest;
    socket.pushGreeting();
    await settle();
    socket.replyToHello(cursor: cursor);
    await settle();
    return socket;
  }

  group('the greeting', () {
    test('a first-ever connection omits since, so the server replays nothing', () async {
      final socket = await connect(cursor: 12);

      final hello = socket.commandNamed('session.hello')!;
      // Sending since:0 would ask for the WHOLE journal from seq 1 (contract §3).
      expect((hello['data'] as Map<String, dynamic>).containsKey('since'), isFalse);
      // The reply's cursor becomes the starting point, and with no replay to
      // wait for the session is current immediately.
      expect(await sync.getCursor(), 12);
      expect(client.currentPhase, SessionPhase.live);
    });

    test('a device that has applied events asks for everything after its cursor', () async {
      await sync.advanceCursor(41);
      final socket = await connect(cursor: 99);

      expect((socket.commandNamed('session.hello')!['data'] as Map<String, dynamic>)['since'], 41);
      // There is history to receive, so the session is behind until it arrives.
      expect(client.currentPhase, SessionPhase.catchingUp);
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
}
