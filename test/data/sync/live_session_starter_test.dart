import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/entity/chat/chat_entity.dart';
import 'package:nox_app/data/local/chat/chat_dao.dart';
import 'package:nox_app/data/local/chat/message_dao.dart';
import 'package:nox_app/data/mapper/chat/chat_mapper.dart';
import 'package:nox_app/data/mapper/chat/chat_wire_mapper.dart';
import 'package:nox_app/data/mapper/chat/message_mapper.dart';
import 'package:nox_app/data/mapper/chat/message_wire_mapper.dart';
import 'package:nox_app/data/remote/api_client.dart';
import 'package:nox_app/data/remote/pinned_http_client.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/repository/app/session_repository_impl.dart';
import 'package:nox_app/data/service/tor/fake_tor_service.dart';
import 'package:nox_app/data/sync/attachment_prefetch_service.dart';
import 'package:nox_app/data/sync/connection/access_key_registrar.dart';
import 'package:nox_app/data/sync/connection/connection_path_selector.dart';
import 'package:nox_app/data/sync/live_session_starter.dart';
import 'package:nox_app/data/sync/sync_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/domain/repository/connection/access_key_repository.dart';
import 'package:nox_app/domain/repository/connection/server_addresses_repository.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';
import 'package:nox_app/domain/service/attachment_download_service.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:nox_app/domain/service/app_lifecycle_service.dart';
import 'package:nox_app/domain/service/network_change_service.dart';
import 'package:nox_app/general/pairing/device_keys.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../remote/socket/fake_socket.dart';
import 'connection/fake_direct_prober.dart';

/// The client half of pairing and revocation, at the points where getting it
/// wrong destroys an installation rather than merely inconveniencing it.
///
/// The state it decides from is covered first, then the starter itself is
/// built over a fake socket: it is registered only on the dev environment, but
/// nothing stops a test from constructing it, and the decisions that bricked an
/// install twice - a greeting sent with nothing to greet with, and a refusal
/// read as a revocation - live in the object, not in the storage it reads.
/// Two fingerprints, distinct on sight. Their VALUES mean nothing here - the
/// starter only carries them - so a readable pair beats a real hash.
const String kPinA = 'A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=';
const String kPinB = 'ZZZZv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SessionRepositoryImpl session;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    final prefs = await SharedPreferences.getInstance();
    session = SessionRepositoryImpl(const FlutterSecureStorage(), prefs);
  });
  tearDown(() async => getIt.reset());

  test('an install that has not paired holds the connection instead of greeting', () async {
    // The window `pair` runs in. Greeting here would be an unsigned hello, the
    // server refuses it, and the refusal reads as a revocation - which wipes
    // the key and address the sign-in in progress just wrote, spending the
    // one-shot claim token for nothing.
    expect((await session.readSession()).data, isNull);

    const credentials = GreetingCredentials.unpaired();
    expect(credentials.unpaired, isTrue);
    expect(credentials.deviceSeed, isNull, reason: 'nothing to greet with, and nothing claimed');
  });

  test('a paired install greets with the public half of its own key', () async {
    await session.saveIdentifier(identifier: 'tok', onboardingComplete: true);
    final seed = (await session.deviceSecret()).data!;

    final credentials = GreetingCredentials(deviceSeed: seed);

    expect(credentials.unpaired, isFalse);
    expect(await DeviceKeys.publicKey(credentials.deviceSeed!), isNotEmpty);
    // The seed itself is what stays: the socket derives the public half and a
    // signature from it, and neither the seed nor anything derived from a
    // login identifier goes out.
    expect(credentials.label, isNull);
  });

  test('the device key survives a rollback, so a retry is the same install', () async {
    final before = (await session.deviceSecret()).data;
    await session.saveIdentifier(identifier: 'tok', onboardingComplete: false);
    await session.saveServer(address: '10.0.0.1:9000', serverFingerprint: kPinA);

    await session.discardSignIn();

    expect((await session.deviceSecret()).data, before, reason: 'a failed attempt changed no install');
    // The server it pointed at goes, though: leaving it would aim the next
    // connection at a machine this install never paired with.
    expect((await session.serverAddress()).data, isNull);
  });

  test('logout takes the key and the server with it', () async {
    await session.saveIdentifier(identifier: 'tok', onboardingComplete: true);
    final before = (await session.deviceSecret()).data;
    await session.saveServer(address: '10.0.0.1:9000', serverFingerprint: kPinA);

    await session.clear();

    expect((await session.serverAddress()).data, isNull);
    // A new key, because this is a different install of the app as far as the
    // server is concerned - which is why sign-in must never take this path.
    expect((await session.deviceSecret()).data, isNot(before));
  });

  test('an unpaired install decides to hold, and a paired one decides to sign', () async {
    // The two branches of the decision that bricked an install twice: greeting
    // with nothing (refused, read as a revocation, wiped) versus greeting with
    // the key (accepted).
    expect((await session.readSession()).data, isNull);
    const held = GreetingCredentials.unpaired();
    expect(held.unpaired, isTrue);
    expect(held.deviceSeed, isNull);

    await session.saveIdentifier(identifier: 'tok', onboardingComplete: true);
    final seed = (await session.deviceSecret()).data;
    final signing = GreetingCredentials(deviceSeed: seed);
    expect(signing.unpaired, isFalse);
    expect(signing.deviceSeed, isNotNull);
  });

  test('the paired server address is what a later connection uses', () async {
    await session.saveIdentifier(identifier: 'tok', onboardingComplete: true);
    await session.saveServer(address: '10.0.0.5:9000', serverFingerprint: kPinA);

    // Not the build-time address: pairing with the server a person presented
    // and then talking to another one is the opposite of "your own server".
    expect((await session.serverAddress()).data, '10.0.0.5:9000');
  });

  group('the starter itself, over a fake socket', () {
    late FakeSocketFactory factory;
    late NoxSocketClient socket;
    late LiveSessionStarter starter;
    late PinnedHttpClient pinned;
    late FakeDirectProber prober;
    late FakeTorService tor;

    setUp(() async {
      await getIt<AppConfigRepository>().initialize(flavorType: AppFlavorType.stage);
      factory = FakeSocketFactory();
      socket = NoxSocketClient(factory, getIt<SyncRepository>());
      final sync = SyncService(
        socket,
        getIt<SyncRepository>(),
        getIt<ChatDao>(),
        getIt<MessageDao>(),
        getIt<ChatMapper>(),
        getIt<ChatWireMapper>(),
        getIt<MessageMapper>(),
        getIt<MessageWireMapper>(),
        getIt<OutboxRepository>(),
        getIt<ServerAddressesRepository>(),
      );
      pinned = PinnedHttpClient();
      prober = FakeDirectProber();
      tor = FakeTorService();
      final selector = ConnectionPathSelector.forTest(
        prober,
        tor,
        getIt<ServerAddressesRepository>(),
        getIt<AccessKeyRepository>(),
        getIt<NetworkChangeService>(),
        getIt<AppLifecycleService>(),
        socket,
      );
      starter = LiveSessionStarter(
        socket,
        sync,
        getIt<SyncRepository>(),
        getIt<AppConfigRepository>(),
        session,
        getIt<ChatRepository>(),
        getIt<MessageRepository>(),
        getIt<OutboxRepository>(),
        getIt<FileRepository>(),
        pinned,
        selector,
        AccessKeyRegistrar(socket, getIt<AccessKeyRepository>()),
        getIt<ServerAddressesRepository>(),
        tor,
      );
    });
    tearDown(() async => starter.stop());

    /// A server reachable only through its onion address: the direct ones say
    /// nothing, Tor works, and this device's key is registered there.
    Future<void> onlyThroughTor() async {
      prober.home = <String>{};
      tor.supported = true;
      await getIt<ServerAddressesRepository>().saveFromServer(direct: const <String>[], onion: '${'a' * 56}.onion:443');
      await getIt<AccessKeyRepository>().deviceKey();
      await getIt<AccessKeyRepository>().markRegistered(true);
    }

    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('an install with no paired server opens no socket at all', () async {
      await starter.start();
      await settle();

      // Not the build-time address as a fallback: a device that paired with one
      // machine must never end up talking to another.
      expect(factory.created, isEmpty);
    });

    test('it connects to the address the pairing link carried', () async {
      await session.saveIdentifier(identifier: 'tok', onboardingComplete: true);
      await session.saveServer(address: '10.0.0.5:9000', serverFingerprint: kPinA);

      await starter.start();
      await settle();

      expect(factory.created, hasLength(1));
      expect(socket.currentPhase, isNot(equals(null)));
    });

    test('it dials wss, with no way to ask for anything else', () async {
      await session.saveIdentifier(identifier: 'tok', onboardingComplete: true);
      await session.saveServer(address: '10.0.0.5:9000', serverFingerprint: kPinA);

      await starter.start();
      await settle();

      expect(factory.urls.single.scheme, 'wss');
      expect(factory.urls.single.toString(), 'wss://10.0.0.5:9000/ws');
    });

    test('the fingerprint from the link reaches the thing that checks certificates', () async {
      // Threaded on every start rather than read once: the client is a
      // singleton built long before anybody pairs, and a naive implementation
      // would pin nothing at all for the life of a fresh install.
      expect(pinned.pinnedFingerprint, isNull);

      await session.saveIdentifier(identifier: 'tok', onboardingComplete: true);
      await session.saveServer(address: '10.0.0.5:9000', serverFingerprint: kPinA);
      await starter.start();
      await settle();

      expect(pinned.pinnedFingerprint, kPinA);
    });

    test('pairing with a DIFFERENT server pins the new one, not the cached one', () async {
      await session.saveIdentifier(identifier: 'tok', onboardingComplete: true);
      await session.saveServer(address: '10.0.0.5:9000', serverFingerprint: kPinA);
      await starter.start();
      await settle();
      expect(pinned.pinnedFingerprint, kPinA);

      // Logout, then pair with another machine - the sequence a person goes
      // through when they rebuild their server.
      await starter.stop();
      expect(pinned.pinnedFingerprint, isNull, reason: 'a logout leaves nothing this install may talk to');
      await session.clear();
      await session.saveIdentifier(identifier: 'tok2', onboardingComplete: true);
      await session.saveServer(address: '10.0.0.9:9000', serverFingerprint: kPinB);

      await starter.start();
      await settle();

      expect(pinned.pinnedFingerprint, kPinB);
    });

    test('a paired address with no fingerprint opens no socket (FR-009)', () async {
      // "Nothing to check against" is a refusal, never a waiver. Reachable by a
      // half-written session, and connecting anyway would accept whatever
      // answered at that address - which is the state this phase ends.
      await session.saveIdentifier(identifier: 'tok', onboardingComplete: true);
      await session.saveServer(address: '10.0.0.5:9000', serverFingerprint: kPinA);
      await FlutterSecureStorage().delete(key: 'session.server_fingerprint');

      await starter.start();
      await settle();

      expect(factory.created, isEmpty);
      expect(pinned.pinnedFingerprint, isNull);
    });

    group('the world is named by the server key (FR-011, FR-012)', () {
      Future<void> paired() async {
        await session.saveIdentifier(identifier: 'tok', onboardingComplete: true);
        await session.saveServer(address: '10.0.0.5:9000', serverFingerprint: kPinA);
      }

      Future<void> aChat() => getIt<ChatDao>().upsert(
        const ChatEntity(
          id: 'c_1',
          name: 'Kept',
          lastMessagePreview: 'p',
          lastMessageAt: '2026-01-01T00:00:00.000Z',
          unreadCount: 0,
          lastOpenedSeq: null,
        ),
      );

      test('a fresh install names it by the fingerprint', () async {
        await paired();
        await starter.start();
        await settle();

        expect(await getIt<SyncRepository>().getEpoch(), 'fp:$kPinA');
      });

      test('a world named by the address before this phase is renamed, not wiped', () async {
        // Every install that updates carries one. Wiping it would empty every
        // chat on every device of every person, once, on update.
        await paired();
        await getIt<SyncRepository>().setEpoch('live:10.0.0.5:9000');
        await aChat();

        await starter.start();
        await settle();

        expect(await getIt<SyncRepository>().getEpoch(), 'fp:$kPinA');
        expect(await getIt<ChatDao>().getById('c_1'), isNotNull, reason: 'the same server, so the same world');
      });

      test('another key is another world, and the old one goes', () async {
        await paired();
        await getIt<SyncRepository>().setEpoch('fp:$kPinB');
        await aChat();

        await starter.start();
        await settle();

        expect(await getIt<SyncRepository>().getEpoch(), 'fp:$kPinA');
        expect(await getIt<ChatDao>().getById('c_1'), isNull);
      });

      test('another world stops the downloads before it wipes their cache (phase 043)', () async {
        await paired();
        await getIt<SyncRepository>().setEpoch('fp:$kPinB');
        final cache = Directory('${(await getApplicationCacheDirectory()).path}/nox_attachments')..createSync(recursive: true);
        final sentinel = File('${cache.path}/f_old.bin')..writeAsBytesSync([1]);
        final downloads = _CacheWatchingDownloads(sentinel);
        getIt.allowReassignment = true;
        getIt.registerSingleton<AttachmentDownloadService>(downloads);

        await starter.start();
        await settle();

        expect(downloads.cacheStillThereAtReset, isTrue, reason: 'stopped first, then the cache goes');
        expect(sentinel.existsSync(), isFalse);
      });

      test('another world empties the picture queue before it stops the downloads, and a failed stop still lets the cache go', () async {
        await paired();
        await getIt<SyncRepository>().setEpoch('fp:$kPinB');
        final cache = Directory('${(await getApplicationCacheDirectory()).path}/nox_attachments')..createSync(recursive: true);
        final sentinel = File('${cache.path}/f_old.bin')..writeAsBytesSync([1]);
        final order = <String>[];
        getIt.allowReassignment = true;
        getIt
          ..registerSingleton<AttachmentDownloadService>(_FailingDownloads(order))
          ..registerSingleton<AttachmentPrefetchService>(_OrderedPrefetch(order));

        await starter.start();
        await settle();

        expect(order, ['prefetch', 'downloads'], reason: 'the worker must not start the old world\'s next picture into the wipe');
        expect(sentinel.existsSync(), isFalse, reason: 'a stop that failed does not keep the old world\'s bytes');
      });

      test('another world takes a chat still waiting to be created with it (phase 041, FR-021)', () async {
        // Made against the old server's world: created on this one it would be
        // a chat nobody asked this server for, under a name from elsewhere.
        await paired();
        await getIt<SyncRepository>().setEpoch('fp:$kPinB');
        await getIt<ChatDao>().upsert(
          const ChatEntity(
            id: 'c_00000000000000000000000000000041',
            name: 'Kitchen',
            lastMessagePreview: '',
            lastMessageAt: '2026-01-01T00:00:00.000Z',
            unreadCount: 0,
            lastOpenedSeq: null,
            creation: 'pending',
          ),
        );

        await starter.start();
        await settle();

        expect(await getIt<ChatRepository>().pendingCreations(), isEmpty);
      });

      test('the same key leaves everything where it is', () async {
        await paired();
        await getIt<SyncRepository>().setEpoch('fp:$kPinA');
        await aChat();

        await starter.start();
        await settle();

        expect(await getIt<ChatDao>().getById('c_1'), isNotNull);
      });
    });

    test('another key at a direct address is "not home": the ladder goes on (FR-005)', () async {
      // An address is a place. On another network the same 192.168.1.20 is
      // somebody else's machine, and calling that "not your server" would put
      // the banner up every time this person left home.
      await session.saveIdentifier(identifier: 'tok', onboardingComplete: true);
      await session.saveServer(address: '10.0.0.5:9000', serverFingerprint: kPinA);
      await starter.start();
      await settle();
      expect(factory.created, hasLength(1));

      factory.latest.refusePin();
      await settle();

      expect(socket.currentPhase, isNot(SessionPhase.serverMismatch));
      for (var i = 0; i < 300 && factory.created.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(factory.created, hasLength(2), reason: 'the next path is tried');
      expect((await session.readSession()).data, isNotNull, reason: 'nothing was wiped');
    });

    test('the socket dials the onion address when no direct one answers (US1)', () async {
      await session.saveIdentifier(identifier: 'tok', onboardingComplete: true);
      await session.saveServer(address: '10.0.0.5:9000', serverFingerprint: kPinA);
      await onlyThroughTor();

      await starter.start();
      await settle();

      expect(factory.urls.single.toString(), 'wss://${'a' * 56}.onion/ws');
      expect(tor.target?.host, '${'a' * 56}.onion');
      // The bytes go the same way, through the bridge the Tor client opened.
      expect(pinned.onionBridge?.call()?.port, 9150);
    });

    test('attachment bytes follow the path the socket took (FR-009)', () async {
      await session.saveIdentifier(identifier: 'tok', onboardingComplete: true);
      await session.saveServer(address: '10.0.0.5:9000', serverFingerprint: kPinA);
      await onlyThroughTor();
      await starter.start();
      await settle();

      factory.latest.pushGreeting();
      for (var i = 0; i < 40 && factory.latest.commandNamed('session.hello') == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      factory.latest.replyToHello(cursor: 0);
      for (var i = 0; i < 40 && !getIt<ApiClient>().dio.options.baseUrl.contains('.onion'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(getIt<ApiClient>().dio.options.baseUrl, 'https://${'a' * 56}.onion');
    });

    test('another key behind the onion address stops the ladder, and the retry is the way back', () async {
      await session.saveIdentifier(identifier: 'tok', onboardingComplete: true);
      await session.saveServer(address: '10.0.0.5:9000', serverFingerprint: kPinA);
      await onlyThroughTor();
      await starter.start();
      await settle();
      expect(factory.created, hasLength(1));

      factory.latest.refusePin();
      await settle();

      expect(socket.currentPhase, SessionPhase.serverMismatch);
      // No ladder. Waited out well past the first rung: an app that kept
      // calling would show "no connection" for ever over a server that answers
      // perfectly well and will never be accepted.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(factory.created, hasLength(1), reason: 'nothing may retry a refusal on its own');

      // The banner action. Without it the app never comes back, not even once
      // the cause is fixed.
      await starter.restart();
      await settle();

      expect(factory.created, hasLength(2));
      expect(socket.currentPhase, isNot(SessionPhase.serverMismatch));
    });

    group('Try again on No connection (phase 042)', () {
      Future<void> paired() async {
        await session.saveIdentifier(identifier: 'tok', onboardingComplete: true);
        await session.saveServer(address: '10.0.0.5:9000', serverFingerprint: kPinA);
      }

      test('a restart asked for while one is under way joins it: one stop and one start', () async {
        await paired();
        await starter.start();
        await settle();
        expect(factory.created, hasLength(1));

        final first = starter.restart();
        final second = starter.restart();
        expect(identical(first, second), isTrue, reason: 'two presses during one restart are one restart');
        await Future.wait([first, second]);
        await settle();

        expect(factory.created, hasLength(2));
      });

      test('a restart after the last one finished is a new one', () async {
        await paired();
        await starter.start();
        await settle();

        await starter.restart();
        await settle();
        await starter.restart();
        await settle();

        expect(factory.created, hasLength(3));
      });

      test('after a restart the path is asked for at once, not after the rung the ladder was waiting out (SC-002)', () async {
        await paired();
        prober.home = <String>{};
        await starter.start();
        // No address answers and there is no Tor: the round fails, and the
        // socket waits out its first rung - about a second.
        for (var i = 0; i < 200 && socket.currentPhase != SessionPhase.disconnected; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(socket.currentPhase, SessionPhase.disconnected);
        final asked = prober.rounds.length;
        final watch = Stopwatch()..start();

        await starter.restart();
        for (var i = 0; i < 100 && prober.rounds.length == asked; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }

        expect(prober.rounds.length, greaterThan(asked));
        expect(watch.elapsed, lessThan(const Duration(milliseconds: 500)), reason: 'within a second of the press, well inside the rung');
      });
    });

    test('a refusal does not take the path that wipes the device', () async {
      // The security requirement of the whole phase, asserted as a
      // non-consequence: the revocation path ends in a forced logout with a
      // full local wipe, so routing a bad certificate through it would let
      // anyone able to stand in the middle erase this person's messages on
      // every device they own, by presenting one.
      await session.saveIdentifier(identifier: 'tok', onboardingComplete: true);
      await session.saveServer(address: '10.0.0.5:9000', serverFingerprint: kPinA);
      await onlyThroughTor();
      await starter.start();
      await settle();

      factory.latest.refusePin();
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // Still signed in, still pointed at the same server, still holding the
      // same device key.
      final live = await session.readSession();
      expect(live.data, isNotNull, reason: 'the session survived');
      expect((await session.serverAddress()).data, '10.0.0.5:9000');
      expect((await session.serverFingerprint()).data, kPinA);
    });

    test('an unpaired install connects but says nothing, leaving room for pair', () async {
      // No session at all: this is the state a fresh install signs in from, and
      // greeting here would spend the claim token on a refusal.
      await session.saveServer(address: '10.0.0.5:9000', serverFingerprint: kPinA);

      await starter.start();
      await settle();
      factory.latest.pushGreeting();
      await settle();

      expect(factory.latest.commandNamed('session.hello'), isNull);
      expect(factory.latest.closed, isFalse);
    });

    test('a paired install greets with a signature over the challenge', () async {
      await session.saveIdentifier(identifier: 'tok', onboardingComplete: true);
      await session.saveServer(address: '10.0.0.5:9000', serverFingerprint: kPinA);

      await starter.start();
      await settle();
      factory.latest.pushGreeting();
      for (var i = 0; i < 40 && factory.latest.commandNamed('session.hello') == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      final hello = factory.latest.commandNamed('session.hello');
      expect(hello, isNotNull);
      final args = hello!['data'] as Map<String, dynamic>;
      expect(args['device_key'], isNotEmpty);
      expect(args['signature'], isNotEmpty);
      // The seed is the one thing that must never travel. Compared against the
      // stored value rather than against a shape, because a bug that sent it
      // would send exactly this string.
      final seed = (await session.deviceSecret()).data;
      expect(hello.toString(), isNot(contains(seed!)));
    });

    test('the greeting hands the server\'s identity to the session', () async {
      // The ONE path that reaches _adoptGreeting, and 037 deleted the test that
      // drove it - it asserted the ownership flag this phase removed - without
      // putting an ownership-free one back. What it covers is load-bearing: the
      // author id is what the server stamps on every message, so a regression
      // that stopped adopting it makes own-vs-other detection wrong and every
      // message this person sent comes back looking like somebody else's.
      await session.saveIdentifier(identifier: 'tok', onboardingComplete: true);
      await session.saveServer(address: '10.0.0.5:9000', serverFingerprint: kPinA);

      await starter.start();
      await settle();
      factory.latest.pushGreeting();
      for (var i = 0; i < 40 && factory.latest.commandNamed('session.hello') == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      // A label the device has never seen: the server is the authority on it,
      // and it may have been changed from another device while this one was
      // offline.
      factory.latest.replyToHello(cursor: 0, id: 'u_person_9', label: 'Renamed elsewhere');
      for (var i = 0; i < 40 && (await SharedPreferences.getInstance()).getString('session.author_id') == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      // BOTH halves, because they fail differently: the label is what the
      // person reads, the author id is what own-vs-other keys on.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('session.author_id'), 'u_person_9');
      expect(prefs.getString('session.label'), 'Renamed elsewhere');
    });

    test('a greeting that lands after logout writes nobody back', () async {
      // The guard inside _adoptGreeting, and it IS reachable - the comment that
      // used to sit here said otherwise, which is precisely the argument that
      // would justify deleting the guard.
      //
      // logout() clears the session inside `mutate` and only stops the live
      // channel afterwards, so a phase that flips in that gap - or an adopt
      // already suspended on the session read - resumes with an empty session
      // while the socket still holds the identity the server stated. Without
      // the guard the signed-out device is handed the previous person's author
      // id back, and adoptServerIdentity re-emits their label on watchLabel(),
      // so the account avatars go on naming somebody who just logged out.
      await session.saveIdentifier(identifier: 'tok', onboardingComplete: true);
      await session.saveServer(address: '10.0.0.5:9000', serverFingerprint: kPinA);

      await starter.start();
      await settle();
      factory.latest.pushGreeting();
      for (var i = 0; i < 40 && factory.latest.commandNamed('session.hello') == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      factory.latest.replyToHello(cursor: 5, id: 'u_person_9', label: 'Anna');
      for (var i = 0; i < 40 && (await SharedPreferences.getInstance()).getString('session.author_id') == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      // Reconnect. The server's cursor has moved past ours, so the new
      // connection parks at catchingUp instead of going straight to live -
      // which is what leaves a phase transition still to come.
      final before = factory.created.length;
      await factory.latest.drop();
      for (var i = 0; i < 200 && factory.created.length == before; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      factory.latest.pushGreeting();
      for (var i = 0; i < 40 && factory.latest.commandNamed('session.hello') == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      factory.latest.replyToHello(cursor: 9, id: 'u_person_9', label: 'Anna');
      await settle();

      // Logout, at the point logout() actually reaches: the session is gone and
      // the starter is still listening.
      await session.clear();
      expect((await SharedPreferences.getInstance()).getString('session.author_id'), isNull, reason: 'clear() left the id behind');

      // Catch-up completes, the phase flips to live, and _adoptGreeting fires
      // with the identity still on the socket and nothing behind it.
      factory.latest.pushEvent(seq: 9);
      await settle();
      await settle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('session.author_id'), isNull, reason: 'a greeting wrote a signed-out identity back onto this device');
      expect(prefs.getString('session.label'), isNull, reason: 'the signed-out name came back');
    });

    test('an install with a server but no identifier never greets, and writes nobody', () async {
      // A device that has not paired has nothing to say: `_credentials` answers
      // unpaired, so no `session.hello` leaves at all. Asserted on the frame,
      // not only on storage - "nothing was written" is true of a device that
      // greeted and was refused too, and those are different failures.
      //
      // The guard further in - _adoptGreeting refusing to persist an identity
      // over an empty session - is a DIFFERENT case and has its own test above.
      // This comment used to claim that guard was unreachable; it is reachable
      // through logout, and saying otherwise is the argument for deleting it.
      await session.saveServer(address: '10.0.0.5:9000', serverFingerprint: kPinA);

      await starter.start();
      await settle();
      factory.latest.pushGreeting();
      await settle();

      expect(factory.latest.commandNamed('session.hello'), isNull, reason: 'an unpaired device introduced itself');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('session.author_id'), isNull, reason: 'a pre-pair greeting was written onto this device');
      expect(prefs.getString('session.label'), isNull);
      expect((await session.readSession()).data, isNull);
    });

    test('a refusal while unpaired clears nothing', () async {
      // The brick: a device that has not paired is refused as a matter of
      // course, and treating that as a revocation wiped the key and the address
      // a sign-in in progress had just written.
      await session.saveServer(address: '10.0.0.5:9000', serverFingerprint: kPinA);
      final before = (await session.deviceSecret()).data;

      await starter.start();
      await settle();
      socket.onUnauthenticated?.call();
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect((await session.deviceSecret()).data, before);
      expect((await session.serverAddress()).data, '10.0.0.5:9000');
    });
  });
}

/// Notes whether the cache was still there when every download was stopped.
class _CacheWatchingDownloads implements AttachmentDownloadService {
  _CacheWatchingDownloads(this.sentinel);

  final File sentinel;
  bool? cacheStillThereAtReset;

  @override
  Future<void> reset() async => cacheStillThereAtReset = sentinel.existsSync();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Notes that it was asked to stop every download, then fails to.
class _FailingDownloads implements AttachmentDownloadService {
  _FailingDownloads(this.order);

  final List<String> order;

  @override
  Future<void> reset() async {
    order.add('downloads');
    throw StateError('a download would not stop');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Notes when the picture queue was emptied.
class _OrderedPrefetch implements AttachmentPrefetchService {
  _OrderedPrefetch(this.order);

  final List<String> order;

  @override
  void reset() => order.add('prefetch');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
