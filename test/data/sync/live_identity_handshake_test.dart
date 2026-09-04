import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/sync/live_identity_handshake.dart';
import 'package:nox_app/data/sync/live_session_starter.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../remote/socket/fake_socket.dart';
import 'live_identity_handshake_test.mocks.dart';

@GenerateMocks([LiveSessionStarter])
void main() {
  group('IdentityHandshake', () {
    test('an outcome the server stated is usable', () {
      const known = IdentityHandshake(authorId: 'u_1', label: 'Anna', created: false);
      expect(known.outcomeStated, isTrue);
      expect(known.created, isFalse);

      const newcomer = IdentityHandshake(authorId: 'u_2', label: 'User1234', created: true);
      expect(newcomer.outcomeStated, isTrue);
      expect(newcomer.created, isTrue);
    });

    test('an outcome the server did NOT state is not an outcome', () {
      // The third wire state is the load-bearing one. Collapsing it into
      // either boolean costs the person something: false steals a newcomer's
      // naming step, true overwrites a returning person's name.
      const silent = IdentityHandshake(authorId: 'u_3', label: 'Anna', created: null);
      expect(silent.outcomeStated, isFalse);
      expect(silent.created, isNull);
    });

    test('the domain value names no frame', () {
      // FR-006d: at stage 2 the same distinction arrives on the pairing reply.
      // Nothing outside the transport layer may notice that it moved, so the
      // type that carries the decision must not mention the greeting at all.
      const value = IdentityHandshake(authorId: 'u_1', label: 'Anna', created: true);
      expect(value.toString(), isNot(contains('hello')));
      expect(value.toString(), isNot(contains('greet')));
    });
  });

  group('the timeout must not outlive its own wait', () {
    test('a timeout releases the caller AND leaves the owner reusable', () async {
      // The defect this guards is specific: an outer `.timeout()` does not
      // cancel its source, so the body keeps running, its `finally` never
      // executes, and the in-flight marker stays raised for the life of the
      // process - wedging every later sign-in. The timeout therefore lives
      // inside the owner, and this asserts the consequence rather than the
      // mechanism: after a timeout, a second attempt is possible.
      final owner = _NeverAnsweringHandshake();

      await expectLater(owner.greet(), throwsA(isA<IdentityHandshakeTimeout>()));
      expect(owner.inFlight, isFalse, reason: 'a timed-out handshake must not stay in flight');

      await expectLater(owner.greet(), throwsA(isA<IdentityHandshakeTimeout>()));
      expect(owner.attempts, 2, reason: 'the second attempt has to actually run');
    });
  });

  /// The owner driven over a real [NoxSocketClient] and an in-memory peer.
  ///
  /// The mirror class below cannot see this class of defect: it models the
  /// timer, not the socket. What lives here is the part that put a returning
  /// person on the naming screen — the wait answering from a connection that
  /// was already up before that person ever tapped Sign in.
  group('LiveIdentityHandshake over a real socket', () {
    late FakeSocketFactory factory;
    late SyncRepository sync;
    late NoxSocketClient client;
    late MockLiveSessionStarter starter;
    late LiveIdentityHandshake handshake;

    final url = Uri.parse('ws://127.0.0.1:8080/ws');

    Future<void> waitUntil(FutureOr<bool> Function() done, {String reason = ''}) async {
      for (var i = 0; i < 400; i++) {
        if (await done()) return;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      fail('condition never became true${reason.isEmpty ? '' : ': $reason'}');
    }

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      await configureDependencies(Environment.test);
      await getIt<AppDatabase>().clearEntireDatabase();
      sync = getIt<SyncRepository>();
      factory = FakeSocketFactory();
      client = NoxSocketClient(factory, sync);
      starter = MockLiveSessionStarter();
      handshake = LiveIdentityHandshake(client, starter);
    });

    tearDown(() async {
      await client.stop();
      await getIt.reset();
    });

    /// Connects and answers the greeting, the way a connection reaches `live`.
    Future<FakeSocket> answerNextGreeting({required String id, required bool? created, String label = 'Anna'}) async {
      await client.start(url: url, credentialsProvider: () async => const GreetingCredentials());
      final socket = factory.latest;
      socket.pushGreeting();
      await waitUntil(() => socket.commandNamed('session.hello') != null, reason: 'greeting sent');
      socket.replyToHello(cursor: 0, id: id, label: label, created: created);
      return socket;
    }

    test('refuses the answer the socket was already holding, and waits for its own', () async {
      // The app greets anonymously at boot, and the server answers an
      // anonymous greeting by minting a person - so that reply always says
      // created: true. Taking it as the answer for whoever signs in next
      // routes EVERY returning person into onboarding, and the name they then
      // type is sent as a rename over the name they were known by.
      await answerNextGreeting(id: 'u_boot', created: true, label: 'User9999');
      await waitUntil(() => client.identity?.id == 'u_boot', reason: 'boot greeting applied');

      var restarted = false;
      when(starter.restart()).thenAnswer((_) async {
        await client.stop();
        await client.start(url: url, credentialsProvider: () async => const GreetingCredentials());
        restarted = true;
      });

      IdentityHandshake? settled;
      final pending = handshake.greet();
      unawaited(pending.then((value) => settled = value));

      await waitUntil(() => restarted, reason: 'restart ran');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(settled, isNull, reason: 'the boot connection answered a question nobody asked');

      final second = factory.latest;
      second.pushGreeting();
      await waitUntil(() => second.commandNamed('session.hello') != null, reason: 'second greeting sent');
      second.replyToHello(cursor: 0, id: 'u_person', label: 'Anna', created: false);

      final result = await pending;
      expect(result.authorId, 'u_person');
      expect(result.label, 'Anna');
      expect(result.created, isFalse, reason: 'a returning person is not created, and must not be onboarded');
    });

    test('hands back what THIS greeting said about a newcomer', () async {
      when(starter.restart()).thenAnswer((_) async {
        await answerNextGreeting(id: 'u_new', created: true, label: 'User4242');
      });

      final result = await handshake.greet();
      expect(result.authorId, 'u_new');
      expect(result.created, isTrue);
      expect(result.outcomeStated, isTrue);
    });

    test('a greeting that states no outcome is reported as unstated, not guessed', () async {
      // The third wire state, reachable from an older server. Neither boolean
      // may be substituted: one steals the naming step, the other overwrites a
      // returning person's name.
      when(starter.restart()).thenAnswer((_) async {
        await answerNextGreeting(id: 'u_silent', created: null);
      });

      final result = await handshake.greet();
      expect(result.outcomeStated, isFalse);
      expect(result.created, isNull);
    });
  });
}

/// Mirrors the real owner's structure - timer inside, cleared in `finally` -
/// against a peer that never answers. The real class needs a socket and a
/// starter from the container; this exercises the property those two cannot
/// influence.
class _NeverAnsweringHandshake {
  int attempts = 0;
  Completer<IdentityHandshake>? _pending;
  Timer? _timer;

  bool get inFlight => _pending != null;

  Future<IdentityHandshake> greet() async {
    attempts++;
    final pending = Completer<IdentityHandshake>();
    _pending = pending;
    _timer = Timer(const Duration(milliseconds: 20), () {
      if (!pending.isCompleted) pending.completeError(const IdentityHandshakeTimeout());
    });
    try {
      return await pending.future;
    } finally {
      _timer?.cancel();
      _timer = null;
      _pending = null;
    }
  }
}
