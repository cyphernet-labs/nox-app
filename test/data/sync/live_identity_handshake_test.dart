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
import 'package:nox_app/domain/model/session/pair_refusal.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:nox_app/general/pairing/pairing_link.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../remote/socket/fake_socket.dart';
import 'live_identity_handshake_test.mocks.dart';

/// A real link the parser accepts (the contract's `minimal` vector): the
/// pending path runs after parsing, and a placeholder would fail before
/// reaching what these tests are about.
const kTestLink = 'nox://pair/A6CapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODwEGwKgBFCD7';

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

    test('a short wait gives up on its own deadline, once the restart is done', () async {
      // How sign-in waits after a pairing: through Tor the answer can be a
      // minute away, and nothing waits on it.
      var restarted = false;
      when(starter.restart()).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        restarted = true;
      });
      final watch = Stopwatch()..start();

      await expectLater(handshake.greet(within: const Duration(milliseconds: 50)), throwsA(isA<IdentityHandshakeTimeout>()));

      expect(restarted, isTrue, reason: 'the restart is always awaited');
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(handshake.inFlight, isFalse);
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

    test('a code that is not a pairing refusal is not reported as a spent link', () async {
      // Contract §2.1: an unknown code is `internal` and retryable. Calling a
      // server hiccup "this link cannot be used" sends the person hunting for
      // an invite they already have.
      when(starter.restart()).thenAnswer((_) async {
        await client.stop();
        await client.start(url: url, credentialsProvider: () async => const GreetingCredentials.unpaired());
        factory.latest.pushGreeting();
      });

      Object? failed;
      unawaited(
        handshake.pair(link: PairingLink.parse(kTestLink), platform: 'ios').catchError((Object e) {
          failed = e;
          return const IdentityHandshake(authorId: '', label: '', created: null);
        }),
      );

      await waitUntil(() => factory.created.isNotEmpty && factory.latest.commandNamed('pair') != null, reason: 'presented');
      final socket = factory.latest;
      socket.reply(socket.sent.indexWhere((f) => f['cmd'] == 'pair'), ok: false, code: 'internal');

      await waitUntil(() => failed != null, reason: 'the failure arrived');
      // Not PairingRefused: the link is fine, the server hiccupped.
      expect(failed, isA<PairingFailed>());
    });

    test('pairing finishes on the reply, with no waiting state to fall into', () async {
      when(starter.restart()).thenAnswer((_) async {
        await client.stop();
        await client.start(url: url, credentialsProvider: () async => const GreetingCredentials.unpaired());
        factory.latest.pushGreeting();
      });

      IdentityHandshake? settled;
      unawaited(handshake.pair(link: PairingLink.parse(kTestLink), platform: 'ios').then((v) => settled = v));

      await waitUntil(() => factory.created.isNotEmpty && factory.latest.commandNamed('pair') != null, reason: 'presented');
      final socket = factory.latest;
      socket.reply(
        socket.sent.indexWhere((f) => f['cmd'] == 'pair'),
        data: {
          'identity': {'id': 'u_me', 'label': 'User3140', 'created': true},
        },
      );

      await waitUntil(() => settled != null, reason: 'the identity arrived');
      expect(settled!.authorId, 'u_me');
      expect(settled!.created, isTrue);
    });

    test('pairing carries the link token - no device key (phase 044) and no access key (phase 045)', () async {
      when(starter.restart()).thenAnswer((_) async {
        await client.stop();
        await client.start(url: url, credentialsProvider: () async => const GreetingCredentials.unpaired());
        factory.latest.pushGreeting();
      });

      unawaited(handshake.pair(link: PairingLink.parse(kTestLink), platform: 'ios').then((_) {}, onError: (Object _) {}));
      await waitUntil(() => factory.created.isNotEmpty && factory.latest.commandNamed('pair') != null, reason: 'presented');

      final sent = factory.latest.commandNamed('pair')!['data'] as Map<String, dynamic>;
      expect(sent['token'], PairingLink.parse(kTestLink).token);
      expect(sent.containsKey('access_key'), isFalse, reason: 'the onion address opens for no key');
      expect(sent.containsKey('device_key'), isFalse, reason: 'the server takes it from the connection');
    });
  });

  /// An invite pairs only once the device that issued it answers (phase 046,
  /// contract §8A): the wait, what can end it, and that nothing is paired
  /// before it ends.
  group('an invite that waits for approval (phase 046)', () {
    late FakeSocketFactory factory;
    late NoxSocketClient client;
    late MockLiveSessionStarter starter;
    late LiveIdentityHandshake handshake;

    final url = Uri.parse('ws://127.0.0.1:8080/ws');
    final link = PairingLink.parse(kTestLink);

    Future<void> waitUntil(FutureOr<bool> Function() done, {String reason = ''}) async {
      for (var i = 0; i < 400; i++) {
        if (await done()) return;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      fail('condition never became true${reason.isEmpty ? '' : ': $reason'}');
    }

    int count(FakeSocket socket, String cmd) => socket.sent.where((f) => f['cmd'] == cmd).length;
    int last(FakeSocket socket, String cmd) => socket.sent.lastIndexWhere((f) => f['cmd'] == cmd);

    const pending = <String, dynamic>{'status': 'pending', 'request_id': 'r_5b0c2e7a91d4f3a6', 'expires_at': 1790000600};
    const anna = <String, dynamic>{
      'identity': {'id': 'u_anna', 'label': 'Anna', 'created': false},
    };

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      await configureDependencies(Environment.test);
      await getIt<AppDatabase>().clearEntireDatabase();
      factory = FakeSocketFactory();
      // A short ladder, so a lost connection comes back within the test.
      client = NoxSocketClient.forTest(factory, getIt<SyncRepository>(), minBackoff: const Duration(milliseconds: 10));
      starter = MockLiveSessionStarter();
      handshake = LiveIdentityHandshake(client, starter);
      // The channel comes up unpaired, the way the starter brings it up for a
      // pairing: held open, no greeting.
      when(starter.restart()).thenAnswer((_) async {
        await client.stop();
        await client.start(url: url, credentialsProvider: () async => const GreetingCredentials.unpaired());
        factory.latest.pushGreeting();
      });
    });

    tearDown(() async {
      await client.stop();
      await getIt.reset();
    });

    /// Starts a pairing and answers its first presentation with "pending".
    Future<({Future<IdentityHandshake> result, FakeSocket socket, List<PairingPending> reported})> waiting({DateTime? until}) async {
      final reported = <PairingPending>[];
      final result = handshake.pair(link: link, platform: 'ios', waitUntil: until, onPending: reported.add);
      result.ignore();
      await waitUntil(() => factory.created.isNotEmpty && factory.latest.commandNamed('pair') != null);
      final socket = factory.latest;
      socket.reply(last(socket, 'pair'), data: pending);
      await waitUntil(() => reported.isNotEmpty);
      return (result: result, socket: socket, reported: reported);
    }

    test('the request waits, and nothing is paired until the device that issued the invite answers', () async {
      final wait = await waiting();
      IdentityHandshake? settled;
      unawaited(wait.result.then((v) => settled = v, onError: (Object _) {}));

      expect(wait.reported.single.requestId, 'r_5b0c2e7a91d4f3a6');
      expect(wait.reported.single.expiresAt, DateTime.fromMillisecondsSinceEpoch(1790000600 * 1000, isUtc: true));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(settled, isNull, reason: 'pending is not paired (SC-002)');
    });

    test('a new wait gives itself the invite\'s ten minutes and a little more, by this device\'s clock', () async {
      final before = DateTime.now();
      final wait = await waiting();

      final until = wait.reported.single.waitUntil;
      expect(until.isAfter(before.add(const Duration(minutes: 10))), isTrue);
      expect(until.isBefore(DateTime.now().add(LiveIdentityHandshake.approvalWindow)), isTrue);
    });

    test('a resumed wait keeps the deadline it was given (FR-011)', () async {
      final until = DateTime.now().add(const Duration(minutes: 4));
      final wait = await waiting(until: until);

      expect(wait.reported.single.waitUntil, until);
    });

    test('Allow pairs: the outcome event is answered by presenting the token again', () async {
      final wait = await waiting();

      wait.socket.pushEvent(seq: 0, event: 'pair.resolved', data: const {'outcome': 'allowed', ...anna});
      await waitUntil(() => count(wait.socket, 'pair') == 2, reason: 'the token goes out again');
      wait.socket.reply(last(wait.socket, 'pair'), data: anna);

      final paired = await wait.result;
      expect(paired.authorId, 'u_anna');
      expect(paired.created, isFalse, reason: 'the person existed: no naming step');
    });

    test('Deny ends the wait as declined', () async {
      final wait = await waiting();

      wait.socket.pushEvent(seq: 0, event: 'pair.resolved', data: const {'outcome': 'denied'});
      await waitUntil(() => count(wait.socket, 'pair') == 2, reason: 'the token goes out again');
      wait.socket.reply(
        last(wait.socket, 'pair'),
        data: const {'status': 'denied', 'request_id': 'r_5b0c2e7a91d4f3a6', 'expires_at': 1790000600},
      );

      await expectLater(wait.result, throwsA(isA<PairingRefused>().having((e) => e.reason, 'reason', PairRefusal.declined)));
    });

    test('the server running the time out ends the wait as an expired link', () async {
      final wait = await waiting();

      wait.socket.pushEvent(seq: 0, event: 'pair.resolved', data: const {'outcome': 'expired'});
      await waitUntil(() => count(wait.socket, 'pair') == 2, reason: 'the token goes out again');
      wait.socket.reply(
        last(wait.socket, 'pair'),
        data: const {'status': 'expired', 'request_id': 'r_5b0c2e7a91d4f3a6', 'expires_at': 1790000600},
      );

      await expectLater(wait.result, throwsA(isA<PairingRefused>().having((e) => e.reason, 'reason', PairRefusal.expired)));
    });

    test('an outcome event the repeat does not bear out is not this request\'s, and the wait goes on', () async {
      // The event names no request. One left over from an earlier request of
      // this same device would otherwise end this one.
      final wait = await waiting();
      Object? ended;
      unawaited(wait.result.then((v) => ended = v, onError: (Object e) => ended = e));

      wait.socket.pushEvent(seq: 0, event: 'pair.resolved', data: const {'outcome': 'denied'});
      await waitUntil(() => count(wait.socket, 'pair') == 2, reason: 'the token goes out again');
      wait.socket.reply(last(wait.socket, 'pair'), data: pending);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(ended, isNull, reason: 'still waiting');

      wait.socket.pushEvent(seq: 0, event: 'pair.resolved', data: const {'outcome': 'allowed', ...anna});
      await waitUntil(() => count(wait.socket, 'pair') == 3, reason: 'asked again');
      wait.socket.reply(last(wait.socket, 'pair'), data: anna);
      expect((await wait.result).authorId, 'u_anna');
    });

    test('an outcome that arrives on the heels of "pending" is not lost', () async {
      // Listened for before the token went out: the issuing device can answer
      // within a frame of the request opening.
      final reported = <PairingPending>[];
      final result = handshake.pair(link: link, platform: 'ios', onPending: reported.add);
      await waitUntil(() => factory.created.isNotEmpty && factory.latest.commandNamed('pair') != null, reason: 'presented');
      final socket = factory.latest;
      socket.reply(last(socket, 'pair'), data: pending);
      socket.pushEvent(seq: 0, event: 'pair.resolved', data: const {'outcome': 'allowed', ...anna});

      await waitUntil(() => count(socket, 'pair') == 2, reason: 'the token goes out again');
      socket.reply(last(socket, 'pair'), data: anna);
      expect((await result).authorId, 'u_anna');
    });

    test('a lost connection does not lose the wait: the token is presented again on the next one', () async {
      final wait = await waiting();

      await wait.socket.drop();
      await waitUntil(() => factory.created.length == 2, reason: 'the client reconnects');
      final next = factory.latest;
      next.pushGreeting();
      await waitUntil(() => next.commandNamed('pair') != null, reason: 'presented on the new connection');
      expect(
        (next.commandNamed('pair')!['data'] as Map<String, dynamic>)['token'],
        link.token,
        reason: 'the same request, by the same token',
      );
      next.reply(last(next, 'pair'), data: anna);

      expect((await wait.result).authorId, 'u_anna');
    });

    test('a server hiccup on a repeat is no answer, and the wait goes on', () async {
      final wait = await waiting();
      Object? ended;
      unawaited(wait.result.then((v) => ended = v, onError: (Object e) => ended = e));

      await client.reconnect();
      final next = factory.latest;
      next.pushGreeting();
      await waitUntil(() => next.commandNamed('pair') != null, reason: 'presented on the new connection');
      next.reply(last(next, 'pair'), ok: false, code: 'internal');
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(ended, isNull, reason: 'the request is still there');
    });

    test('Cancel withdraws the request by its token, and the wait ends as cancelled', () async {
      final wait = await waiting();

      final cancelling = handshake.cancelPairing();
      await waitUntil(() => wait.socket.commandNamed('pair.cancel') != null, reason: 'pair.cancel is sent');
      expect(wait.socket.commandNamed('pair.cancel')!['data'], {'token': link.token});
      wait.socket.reply(last(wait.socket, 'pair.cancel'), data: const {});
      // What it ended as is read back, as for any other outcome.
      await waitUntil(() => count(wait.socket, 'pair') == 2, reason: 'the outcome is read');
      wait.socket.reply(
        last(wait.socket, 'pair'),
        data: const {'status': 'cancelled', 'request_id': 'r_5b0c2e7a91d4f3a6', 'expires_at': 1790000600},
      );
      await cancelling;

      await expectLater(wait.result, throwsA(isA<PairingCancelled>()));
    });

    test('Cancel after an Allow already landed pairs, rather than leaving a key paired nothing here knows', () async {
      final wait = await waiting();

      unawaited(handshake.cancelPairing());
      await waitUntil(() => wait.socket.commandNamed('pair.cancel') != null, reason: 'pair.cancel is sent');
      wait.socket.reply(last(wait.socket, 'pair.cancel'), data: const {});
      await waitUntil(() => count(wait.socket, 'pair') == 2, reason: 'the outcome is read');
      wait.socket.reply(last(wait.socket, 'pair'), data: anna);

      expect((await wait.result).authorId, 'u_anna');
    });

    test('Cancel with nothing waiting does nothing', () async {
      await handshake.cancelPairing();
      expect(factory.created, isEmpty);
    });

    test('at its own deadline the device asks once more, withdraws a request still open, and calls it expired', () async {
      // A server whose clock runs behind still holds the request: withdrawn on
      // the way out, so no Allow pressed later can pair this key.
      final wait = await waiting(until: DateTime.now().add(const Duration(milliseconds: 150)));

      await waitUntil(() => count(wait.socket, 'pair') == 2, reason: 'asked at the deadline');
      wait.socket.reply(last(wait.socket, 'pair'), data: pending);
      await waitUntil(() => wait.socket.commandNamed('pair.cancel') != null, reason: 'withdrawn');
      wait.socket.reply(last(wait.socket, 'pair.cancel'), data: const {});
      await waitUntil(() => count(wait.socket, 'pair') == 3, reason: 'the outcome is read');
      wait.socket.reply(
        last(wait.socket, 'pair'),
        data: const {'status': 'cancelled', 'request_id': 'r_5b0c2e7a91d4f3a6', 'expires_at': 1790000600},
      );

      await expectLater(wait.result, throwsA(isA<PairingRefused>().having((e) => e.reason, 'reason', PairRefusal.expired)));
    });

    test('at the deadline the server\'s own word wins', () async {
      final wait = await waiting(until: DateTime.now().add(const Duration(milliseconds: 150)));

      await waitUntil(() => count(wait.socket, 'pair') == 2, reason: 'asked at the deadline');
      wait.socket.reply(last(wait.socket, 'pair'), data: anna);

      expect((await wait.result).authorId, 'u_anna');
      expect(wait.socket.commandNamed('pair.cancel'), isNull, reason: 'nothing left to withdraw');
    });

    test('a link the server answers at once still pairs without any waiting', () async {
      // The machine link (contract §8A): no approval, no wait.
      final reported = <PairingPending>[];
      final result = handshake.pair(link: link, platform: 'ios', onPending: reported.add);
      await waitUntil(() => factory.created.isNotEmpty && factory.latest.commandNamed('pair') != null, reason: 'presented');
      factory.latest.reply(
        last(factory.latest, 'pair'),
        data: const {
          'identity': {'id': 'u_me', 'label': 'User3140', 'created': true},
        },
      );

      expect((await result).created, isTrue);
      expect(reported, isEmpty);
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
