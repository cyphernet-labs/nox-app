import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/repository/app/session_repository_impl.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/general/pairing/device_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The client half of pairing and revocation, at the two points where getting
/// it wrong destroys an installation rather than merely inconveniencing it.
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
}
