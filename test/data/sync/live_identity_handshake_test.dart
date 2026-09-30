import 'dart:async';
import 'dart:convert';

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
import 'package:nox_app/data/service/tor/fake_tor_service.dart';
import 'package:nox_app/data/sync/connection/connection_path_selector.dart';
import 'package:nox_app/domain/repository/connection/access_key_repository.dart';
import 'package:nox_app/domain/repository/connection/server_addresses_repository.dart';
import 'package:nox_app/domain/service/app_lifecycle_service.dart';
import 'package:nox_app/domain/service/network_change_service.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:nox_app/general/pairing/pairing_link.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../remote/socket/fake_socket.dart';
import 'connection/fake_direct_prober.dart';
import 'live_identity_handshake_test.mocks.dart';

/// A real link the parser accepts: the pending path runs after parsing, and a
/// placeholder would fail before reaching what these tests are about.
const kTestLink = 'https://nox.app/p/#AQF_AAABH5CjZmMytIk_2XvPJ-jonqlQtYsZD3SB33P1foxqnrVbFo-VEf6WohQoqA1_na5iVUo';

/// A version-2 link (IPv4) from the vectors both sides pin: it lends an onion
/// address on port 443 and a one-time key.
const kTestLinkV2 =
    'https://nox.app/p/#AgHAqAEKH5AAAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eH6ChoqOkpaanqKmqq6ytrq8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0-PwG7QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl8';

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
    late FakeTorService tor;

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
      tor = FakeTorService();
      handshake = LiveIdentityHandshake(
        client,
        starter,
        getIt<AccessKeyRepository>(),
        tor,
        getIt<ServerAddressesRepository>(),
        ConnectionPathSelector.forTest(
          FakeDirectProber(),
          tor,
          getIt<ServerAddressesRepository>(),
          getIt<AccessKeyRepository>(),
          getIt<NetworkChangeService>(),
          getIt<AppLifecycleService>(),
          client,
        ),
      );
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
        handshake.pair(link: PairingLink.parse(kTestLink), deviceKey: 'k', platform: 'ios').catchError((Object e) {
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
      unawaited(handshake.pair(link: PairingLink.parse(kTestLink), deviceKey: 'k', platform: 'ios').then((v) => settled = v));

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

    test('pairing carries this device\'s onion access key (FR-015)', () async {
      when(starter.restart()).thenAnswer((_) async {
        await client.stop();
        await client.start(url: url, credentialsProvider: () async => const GreetingCredentials.unpaired());
        factory.latest.pushGreeting();
      });

      unawaited(handshake.pair(link: PairingLink.parse(kTestLink), deviceKey: 'k', platform: 'ios').then((_) {}, onError: (Object _) {}));
      await waitUntil(() => factory.created.isNotEmpty && factory.latest.commandNamed('pair') != null, reason: 'presented');

      final sent = factory.latest.commandNamed('pair')!['data'] as Map<String, dynamic>;
      final own = (await getIt<AccessKeyRepository>().deviceKey()).data!;
      expect(sent['access_key'], own.publicBase64);
      expect(sent['access_key'], isNot(contains(base64Encode(own.privateKey))), reason: 'only the public half travels');
    });

    group('a version-2 link (FR-020, FR-021)', () {
      AccessKeyRepository keys() => getIt<AccessKeyRepository>();
      final onion = '${'a' * 56}.onion:443';
      InviteAccess? lentDuringPairing;

      void serveTheChannel() {
        when(starter.restart()).thenAnswer((_) async {
          lentDuringPairing = (await keys().invite()).data;
          await client.stop();
          await client.start(url: url, credentialsProvider: () async => const GreetingCredentials.unpaired());
          factory.latest.pushGreeting();
        });
      }

      Future<Object?> pairAndAnswer({required bool ok}) async {
        Object? outcome;
        unawaited(
          handshake
              .pair(link: PairingLink.parse(kTestLinkV2), deviceKey: 'k', platform: 'ios')
              .then((v) => outcome = v, onError: (Object e) => outcome = e),
        );
        await waitUntil(() => factory.created.isNotEmpty && factory.latest.commandNamed('pair') != null, reason: 'presented');
        final socket = factory.latest;
        final index = socket.sent.indexWhere((f) => f['cmd'] == 'pair');
        if (ok) {
          socket.reply(
            index,
            data: {
              'identity': {'id': 'u_me', 'label': 'Anna', 'created': false},
            },
          );
        } else {
          socket.reply(index, ok: false, code: 'invalid_token');
        }
        await waitUntil(() => outcome != null, reason: 'the pairing answered');
        return outcome;
      }

      setUp(() {
        lentDuringPairing = null;
        tor.supported = true;
        serveTheChannel();
      });

      test('it lends its onion address and one-time key for the pairing, and no longer', () async {
        await pairAndAnswer(ok: true);

        expect(lentDuringPairing?.onion, onion, reason: 'there when the channel came up');
        expect(lentDuringPairing?.oneTimeKey, PairingLink.parse(kTestLinkV2).oneTimePriv);
        expect((await keys().invite()).data, isNull, reason: 'gone once the reply is in');
      });

      test('a paired device keeps the onion address, and its own key counts as registered', () async {
        await pairAndAnswer(ok: true);

        expect((await getIt<ServerAddressesRepository>().read()).data?.onion, onion);
        expect((await keys().isRegistered()).data, isTrue);
      });

      test('a refused pairing erases the lent key just the same', () async {
        final outcome = await pairAndAnswer(ok: false);

        expect(outcome, isA<PairingRefused>());
        expect((await keys().invite()).data, isNull);
        expect((await keys().isRegistered()).data, isFalse);
        expect((await getIt<ServerAddressesRepository>().read()).data?.onion, isNull);
      });

      test('where Tor cannot run the lent fields are read and left unused', () async {
        tor.supported = false;

        await pairAndAnswer(ok: true);

        expect(lentDuringPairing, isNull);
        expect((await getIt<ServerAddressesRepository>().read()).data?.onion, isNull);
      });
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
