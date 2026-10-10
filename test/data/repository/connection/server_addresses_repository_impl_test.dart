import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/repository/connection/connection_storage.dart';
import 'package:nox_app/data/repository/connection/server_addresses_repository_impl.dart';
import 'package:nox_app/domain/model/connection/server_addresses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ServerAddressesRepositoryImpl repository;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    repository = ServerAddressesRepositoryImpl(const FlutterSecureStorage());
  });

  test('nothing stored reads as empty', () async {
    expect((await repository.read()).data, ServerAddresses.empty);
  });

  test("what the server said is kept, and so is the last good address across the server's updates", () async {
    await repository.saveFromServer(direct: ['192.168.1.20:8443'], onion: 'abc.onion:443');
    await repository.recordLastGood('192.168.1.20:8443');
    await repository.saveFromServer(direct: ['192.168.1.21:8443'], onion: 'abc.onion:443');
    final addresses = (await repository.read()).data!;
    expect(addresses.direct, ['192.168.1.21:8443']);
    expect(addresses.onion, 'abc.onion:443');
    expect(addresses.lastGood, '192.168.1.20:8443');
  });

  test('a server that stops offering onion clears it', () async {
    await repository.saveFromServer(direct: const [], onion: 'abc.onion:443');
    await repository.saveFromServer(direct: const [], onion: null);
    expect((await repository.read()).data!.onion, isNull);
  });

  test('concurrent writes do not lose each other', () async {
    await Future.wait([
      repository.saveFromServer(direct: ['10.0.0.5:8443'], onion: 'abc.onion:443'),
      repository.recordLastGood('10.0.0.5:8443'),
    ]);
    final addresses = (await repository.read()).data!;
    expect(addresses.direct, ['10.0.0.5:8443']);
    expect(addresses.lastGood, '10.0.0.5:8443');
  });

  test('a greeting through Tor is remembered, and a direct one forgets it', () async {
    // How the next attempt knows to start Tor alongside the direct addresses.
    await repository.saveFromServer(direct: ['10.0.0.5:8443'], onion: 'abc.onion:443');
    await repository.recordGreetedViaTor();
    expect((await repository.read()).data!.viaTorLast, isTrue);
    expect(
      (await ServerAddressesRepositoryImpl(const FlutterSecureStorage()).read()).data!.viaTorLast,
      isTrue,
      reason: 'kept across launches',
    );

    await repository.recordLastGood('10.0.0.5:8443');
    expect((await repository.read()).data!.viaTorLast, isFalse);
    expect((await repository.read()).data!.lastGood, '10.0.0.5:8443');
  });

  test('a clear lands after a write already under way, so nothing survives it', () async {
    // How a logout wipes them: a greeting stored a moment before the channel
    // stopped must not land after the wipe (FR-018).
    final writing = repository.saveFromServer(direct: ['10.0.0.5:8443'], onion: 'abc.onion:443');
    await repository.clear();
    await writing;

    expect((await repository.read()).data, ServerAddresses.empty);
  });

  test('a record this build cannot read is treated as absent', () async {
    FlutterSecureStorage.setMockInitialValues({ConnectionStorage.serverAddresses: '{not json'});
    expect((await repository.read()).data, ServerAddresses.empty);
  });

  test('watch gives what is stored, then every change, and nothing for a write that changes nothing', () async {
    await repository.saveFromServer(direct: ['192.168.1.20:8443'], onion: null);
    final seen = <ServerAddresses>[];
    final sub = repository.watch().listen(seen.add);
    await Future<void>.delayed(Duration.zero);

    await repository.saveFromServer(direct: ['192.168.1.20:8443'], onion: null);
    await repository.saveFromServer(direct: ['192.168.1.30:8443'], onion: null);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(seen.map((a) => a.direct.single), ['192.168.1.20:8443', '192.168.1.30:8443']);
  });

  group('the server and the person (phase 045, FR-015)', () {
    final serverOnion = '${'a' * 56}.onion:443';
    final typedOnion = '${'b' * 56}.onion:443';

    test('a public address the server states replaces the person\'s edit of the address field', () async {
      await repository.saveManual(manualAddress: '10.8.0.2:8443', manualOnion: null);

      await repository.saveFromServer(direct: const ['192.168.1.20:8443'], public: 'nox.example.org:8443');

      final stored = (await repository.read()).data!;
      expect(stored.public, 'nox.example.org:8443');
      expect(stored.manualAddress, isNull);
      expect(stored.fieldAddress('192.168.1.20:8443'), 'nox.example.org:8443');
    });

    test('a field the server leaves out keeps the person\'s edit, and forgets the server\'s old value', () async {
      await repository.saveFromServer(direct: const [], public: 'nox.example.org:8443', onion: serverOnion);
      await repository.saveManual(manualAddress: '10.8.0.2:8443', manualOnion: typedOnion);

      await repository.saveFromServer(direct: const []);

      final stored = (await repository.read()).data!;
      expect(stored.manualAddress, '10.8.0.2:8443');
      expect(stored.manualOnion, typedOnion);
      expect(stored.public, isNull);
      expect(stored.onion, isNull);
      expect(stored.effectiveOnion, typedOnion);
    });

    test('an onion address the server states replaces the person\'s, even a cleared one', () async {
      await repository.saveManual(manualAddress: null, manualOnion: '');
      expect((await repository.read()).data!.effectiveOnion, isNull);

      await repository.saveFromServer(direct: const [], onion: serverOnion);

      final stored = (await repository.read()).data!;
      expect(stored.manualOnion, isNull);
      expect(stored.effectiveOnion, serverOnion);
    });

    test('Use Tor survives what the server says, and is kept across launches', () async {
      await repository.setUseTor(true);
      await repository.saveFromServer(direct: const ['192.168.1.20:8443'], onion: serverOnion);

      expect((await repository.read()).data!.useTor, isTrue);
      expect((await ServerAddressesRepositoryImpl(const FlutterSecureStorage()).read()).data!.useTor, isTrue);
    });

    test('a pairing link replaces everything: its addresses, the edits made on the connection screen, and Use Tor', () async {
      await repository.saveFromServer(direct: const ['10.0.0.1:1'], public: 'old.example.org:1', onion: typedOnion);
      await repository.recordLastGood('10.0.0.1:1');
      await repository.recordGreetedViaTor();

      await repository.saveFromLink(
        direct: const ['192.168.1.20:8443', 'nox.example.org:8443'],
        onion: serverOnion,
        manualAddress: '10.8.0.2:8443',
        manualOnion: '',
        useTor: true,
      );

      final stored = (await repository.read()).data!;
      expect(stored.direct, ['192.168.1.20:8443', 'nox.example.org:8443']);
      expect(stored.onion, serverOnion);
      expect(stored.public, isNull);
      expect(stored.manualAddress, '10.8.0.2:8443');
      expect(stored.manualOnion, '');
      expect(stored.effectiveOnion, isNull, reason: 'the person cleared it');
      expect(stored.useTor, isTrue);
      expect(stored.lastGood, isNull);
      expect(stored.viaTorLast, isFalse);
    });

    test('every field survives the round trip through storage', () async {
      await repository.saveFromServer(direct: const ['192.168.1.20:8443'], public: 'nox.example.org:8443', onion: serverOnion);
      await repository.saveManual(manualAddress: '10.8.0.2:8443', manualOnion: typedOnion);
      await repository.setUseTor(true);
      await repository.recordLastGood('192.168.1.20:8443');
      await repository.recordGreetedViaTor();

      final fresh = (await ServerAddressesRepositoryImpl(const FlutterSecureStorage()).read()).data!;

      expect(fresh, (await repository.read()).data);
      expect(fresh.manualOnion, typedOnion, reason: 'the edit came after the server spoke');
      expect(fresh.useTor, isTrue);
      expect(fresh.public, 'nox.example.org:8443');
    });

    test('watch reports Use Tor turned off', () async {
      await repository.setUseTor(true);
      final seen = <bool>[];
      final sub = repository.watch().listen((a) => seen.add(a.useTor));
      await Future<void>.delayed(Duration.zero);

      await repository.setUseTor(false);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(seen, [true, false]);
    });
  });
}
