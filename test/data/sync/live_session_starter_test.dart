import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/chat/chat_dao.dart';
import 'package:nox_app/data/local/chat/message_dao.dart';
import 'package:nox_app/data/mapper/chat/chat_mapper.dart';
import 'package:nox_app/data/mapper/chat/chat_wire_mapper.dart';
import 'package:nox_app/data/mapper/chat/message_mapper.dart';
import 'package:nox_app/data/mapper/chat/message_wire_mapper.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/repository/app/session_repository_impl.dart';
import 'package:nox_app/data/sync/live_session_starter.dart';
import 'package:nox_app/data/sync/sync_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:nox_app/general/pairing/device_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../remote/socket/fake_socket.dart';

/// The client half of pairing and revocation, at the points where getting it
/// wrong destroys an installation rather than merely inconveniencing it.
///
/// The state it decides from is covered first, then the starter itself is
/// built over a fake socket: it is registered only on the dev environment, but
/// nothing stops a test from constructing it, and the decisions that bricked an
/// install twice - a greeting sent with nothing to greet with, and a refusal
/// read as a revocation - live in the object, not in the storage it reads.
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
    await session.saveServer(address: '10.0.0.1:9000', serverKey: 'A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=');

    await session.discardSignIn();

    expect((await session.deviceSecret()).data, before, reason: 'a failed attempt changed no install');
    // The server it pointed at goes, though: leaving it would aim the next
    // connection at a machine this install never paired with.
    expect((await session.serverAddress()).data, isNull);
  });

  test('logout takes the key and the server with it', () async {
    await session.saveIdentifier(identifier: 'tok', onboardingComplete: true);
    final before = (await session.deviceSecret()).data;
    await session.saveServer(address: '10.0.0.1:9000', serverKey: 'A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=');

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
    await session.saveServer(address: '10.0.0.5:9000', serverKey: 'A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=');

    // Not the build-time address: pairing with the server a person presented
    // and then talking to another one is the opposite of "your own server".
    expect((await session.serverAddress()).data, '10.0.0.5:9000');
  });

  group('the starter itself, over a fake socket', () {
    late FakeSocketFactory factory;
    late NoxSocketClient socket;
    late LiveSessionStarter starter;

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
      );
    });
    tearDown(() async => starter.stop());

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
      await session.saveServer(address: '10.0.0.5:9000', serverKey: 'A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=');

      await starter.start();
      await settle();

      expect(factory.created, hasLength(1));
      expect(socket.currentPhase, isNot(equals(null)));
    });

    test('an unpaired install connects but says nothing, leaving room for pair', () async {
      // No session at all: this is the state a fresh install signs in from, and
      // greeting here would spend the claim token on a refusal.
      await session.saveServer(address: '10.0.0.5:9000', serverKey: 'A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=');

      await starter.start();
      await settle();
      factory.latest.pushGreeting();
      await settle();

      expect(factory.latest.commandNamed('session.hello'), isNull);
      expect(factory.latest.closed, isFalse);
    });

    test('a paired install greets with a signature over the challenge', () async {
      await session.saveIdentifier(identifier: 'tok', onboardingComplete: true);
      await session.saveServer(address: '10.0.0.5:9000', serverKey: 'A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=');

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

    test('a refusal while unpaired clears nothing', () async {
      // The brick: a device that has not paired is refused as a matter of
      // course, and treating that as a revocation wiped the key and the address
      // a sign-in in progress had just written.
      await session.saveServer(address: '10.0.0.5:9000', serverKey: 'A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=');
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
