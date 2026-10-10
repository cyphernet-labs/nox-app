import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/repository/app/session_repository_impl.dart';
import 'package:nox_app/data/repository/connection/connection_storage.dart';
import 'package:nox_app/data/repository/log_repository_impl.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/connection/connection_settings.dart';
import 'package:nox_app/domain/model/session/pending_pairing.dart';
import 'package:nox_app/domain/repository/log_repository.dart';
import 'package:nox_app/general/pairing/device_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SessionRepositoryImpl repository;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repository = SessionRepositoryImpl(const FlutterSecureStorage(), prefs);
  });

  test('reads a null session when no identifier is stored', () async {
    final result = await repository.readSession();
    expect(result.hasData, isTrue);
    expect(result.data, isNull);
  });

  test('saves the identifier and reads it back with label and onboarding flag', () async {
    await repository.saveIdentifier(identifier: 'abc', onboardingComplete: true, label: 'Alice');
    final session = (await repository.readSession()).data;
    expect(session, isNotNull);
    expect(session!.identifier, 'abc');
    expect(session.label, 'Alice');
    expect(session.onboardingComplete, isTrue);
  });

  test('persists onboardingComplete as false when signed in as a new identifier', () async {
    await repository.saveIdentifier(identifier: 'abc', onboardingComplete: false);
    expect((await repository.readSession()).data!.onboardingComplete, isFalse);
  });

  test('setOnboardingComplete flips the flag and caches the label', () async {
    await repository.saveIdentifier(identifier: 'abc', onboardingComplete: false);
    await repository.setOnboardingComplete(label: 'Bob');
    final session = (await repository.readSession()).data!;
    expect(session.onboardingComplete, isTrue);
    expect(session.label, 'Bob');
  });

  test('clear wipes the identifier so the session resolves to null', () async {
    await repository.saveIdentifier(identifier: 'abc', onboardingComplete: true, label: 'Alice');
    await repository.clear();
    expect((await repository.readSession()).data, isNull);
  });

  // The two halves of a session live in different stores, and `deleteAll` is one
  // query against one of them. A key written under options that query does not
  // match survives it with no error to catch - which is how a logout emptied the
  // preferences, left the identifier behind, and put the person who had just
  // signed out on the naming screen with a token for a server gone from the app.
  group('clear does not trust deleteAll', () {
    test('wipes by name, so a sweep that does nothing still empties the session', () async {
      final prefs = await SharedPreferences.getInstance();
      final leaky = SessionRepositoryImpl(const _NoSweepStorage(), prefs);
      await leaky.saveIdentifier(identifier: 'abc', onboardingComplete: true, label: 'Alice');

      expect((await leaky.clear()).hasData, isTrue);
      expect((await leaky.readSession()).data, isNull);
    });

    test('refuses when the identifier survives, and leaves the session whole rather than half', () async {
      final prefs = await SharedPreferences.getInstance();
      final stuck = SessionRepositoryImpl(const _UndeletableIdentityStorage(), prefs);
      await stuck.saveIdentifier(identifier: 'abc', onboardingComplete: true, label: 'Alice');

      final result = await stuck.clear();

      expect(result.hasData, isFalse, reason: 'a wipe that did not happen must not report success');
      // The whole point: the onboarding flag is still there. Removing it while
      // the identifier survives is what strands a logged-out person mid-flow -
      // staying signed in is wrong too, but it is recoverable and it is said
      // out loud.
      final session = (await stuck.readSession()).data;
      expect(session, isNotNull);
      expect(session!.onboardingComplete, isTrue);
      expect(session.label, 'Alice');
    });
  });

  group('advanceOnboardingIfKnown (feature 031)', () {
    test('a greeting that created the person does not end onboarding', () async {
      await repository.saveIdentifier(identifier: 'abc', onboardingComplete: false);
      final moved = await repository.advanceOnboardingIfKnown(created: true);
      expect(moved.data, isFalse);
      expect((await repository.readSession()).data!.onboardingComplete, isFalse);
    });

    test('a reconnect while this process is still naming does NOT end onboarding', () async {
      // The defect this guards is invisible on the wire: the second greeting
      // of a brand-new person says created == false, exactly like the greeting
      // of someone who existed all along. Acting on it swaps the root route
      // away from the naming screen and discards what was typed.
      await repository.saveIdentifier(identifier: 'abc', onboardingComplete: false);
      repository.noteOnboardingStartedHere();

      final moved = await repository.advanceOnboardingIfKnown(created: false);

      expect(moved.data, isFalse);
      expect((await repository.readSession()).data!.onboardingComplete, isFalse);
    });

    test('after a restart the same greeting DOES rescue the device', () async {
      // No in-process memory of having created anyone: this is the device left
      // on the naming screen while the person named themselves elsewhere.
      await repository.saveIdentifier(identifier: 'abc', onboardingComplete: false);

      final moved = await repository.advanceOnboardingIfKnown(created: false);

      expect(moved.data, isTrue);
      expect((await repository.readSession()).data!.onboardingComplete, isTrue);
    });

    test('naming clears the in-process mark, so later greetings act again', () async {
      await repository.saveIdentifier(identifier: 'abc', onboardingComplete: false);
      repository.noteOnboardingStartedHere();
      await repository.setOnboardingComplete(label: 'Anna');

      // Already complete, so nothing moves - but the mark is gone, which is
      // what the next sign-in in this process depends on.
      expect((await repository.advanceOnboardingIfKnown(created: false)).data, isFalse);
      await repository.discardSignIn();
      await repository.saveIdentifier(identifier: 'def', onboardingComplete: false);
      expect((await repository.advanceOnboardingIfKnown(created: false)).data, isTrue);
    });

    test('the flag never retreats: onboarding already done stays done', () async {
      await repository.saveIdentifier(identifier: 'abc', onboardingComplete: true);
      expect((await repository.advanceOnboardingIfKnown(created: true)).data, isFalse);
      expect((await repository.readSession()).data!.onboardingComplete, isTrue);
    });
  });

  group('the paired server (feature 032, phase 044)', () {
    const serverKey = 'oJql9HpnWYAv+VX43C0qFKXJnSO+l/hkEn/5ODRVpPA=';

    test('address and server key survive, so the app talks to the server it paired with', () async {
      await repository.saveServer(address: '10.0.0.5:9000', serverKey: serverKey);

      expect((await repository.serverAddress()).data, '10.0.0.5:9000');
      expect((await repository.serverKey()).data, serverKey);
      expect(await const FlutterSecureStorage().read(key: 'session.server_key'), serverKey);
    });

    test('an install that never paired has neither an address nor a server key', () async {
      expect((await repository.serverAddress()).data, isNull);
      expect((await repository.serverKey()).data, isNull);
    });

    test('logout forgets the server, because the next link brings its own', () async {
      await repository.saveServer(address: '10.0.0.5:9000', serverKey: serverKey);
      await repository.clear();

      expect((await repository.serverAddress()).data, isNull);
      expect((await repository.serverKey()).data, isNull);
    });

    test('a failed sign-in forgets the server it named', () async {
      await repository.saveServer(address: '10.0.0.5:9000', serverKey: serverKey);
      await repository.discardSignIn();

      expect((await repository.serverAddress()).data, isNull);
      expect((await repository.serverKey()).data, isNull);
    });

    test('the device seed is a real 32-byte key, not a random string', () async {
      final seed = (await repository.deviceSecret()).data!;
      // The module opens every channel with it: if this ever stops being a
      // key, every connection fails with an error nobody can trace to here.
      expect(base64.decode(seed).length, 32);
      expect((await DeviceKeys.publicKey(seed)).isNotEmpty, isTrue);
    });
  });

  group('a session paired before phase 044 (FR-025)', () {
    test('an identifier with no server key predates it', () async {
      await repository.saveIdentifier(identifier: 'abc', onboardingComplete: true);
      await const FlutterSecureStorage().write(key: 'session.server_fingerprint', value: 'fp');
      expect((await repository.predatesServerKey()).data, isTrue);
    });

    test('a session with its server key does not', () async {
      await repository.saveServer(address: '10.0.0.5:9000', serverKey: 'oJql9HpnWYAv+VX43C0qFKXJnSO+l/hkEn/5ODRVpPA=');
      await repository.saveIdentifier(identifier: 'abc', onboardingComplete: true);
      expect((await repository.predatesServerKey()).data, isFalse);
    });

    test('no session at all predates nothing - and after the wipe there is none, so it happens once', () async {
      expect((await repository.predatesServerKey()).data, isFalse);
      await repository.saveIdentifier(identifier: 'abc', onboardingComplete: true);
      expect((await repository.predatesServerKey()).data, isTrue);
      await repository.clear();
      expect((await repository.predatesServerKey()).data, isFalse);
    });

    test('a keychain that cannot be read says so, and never claims the session is old', () async {
      // The failure is logged on its way out.
      getIt.allowReassignment = true;
      getIt.registerSingleton<LogRepository>(LoggerLogRepository());
      addTearDown(getIt.reset);
      final prefs = await SharedPreferences.getInstance();
      final locked = SessionRepositoryImpl(const _LockedStorage(), prefs);
      final result = await locked.predatesServerKey();
      expect(result.hasData, isFalse, reason: 'an error, which wipes nothing');
    });

    test('the bootstrap sweep drops the certificate fingerprint the old builds pinned', () async {
      await const FlutterSecureStorage().write(key: 'session.server_fingerprint', value: 'fp');
      expect((await repository.sweepLegacyKeys()).hasData, isTrue);
      expect(await const FlutterSecureStorage().read(key: 'session.server_fingerprint'), isNull);
    });
  });

  group('discardSignIn (feature 031)', () {
    test('undoes the sign-in so the session resolves to null', () async {
      await repository.saveIdentifier(identifier: 'abc', onboardingComplete: false);
      await repository.discardSignIn();
      expect((await repository.readSession()).data, isNull);
    });

    test('keeps the device key - a sign-in that never reached the server changed no install', () async {
      final before = (await repository.deviceSecret()).data;
      await repository.saveIdentifier(identifier: 'abc', onboardingComplete: false);

      await repository.discardSignIn();

      // clear() would rotate it, and the next successful attempt would then
      // register a second device for one install.
      expect((await repository.deviceSecret()).data, before);
    });

    test('clear DOES rotate the device key, which is why sign-in must not use it', () async {
      final before = (await repository.deviceSecret()).data;
      await repository.clear();
      expect((await repository.deviceSecret()).data, isNot(before));
    });
  });

  group('a pairing waiting for approval (phase 046, FR-011)', () {
    final waitUntil = DateTime.utc(2026, 10, 10, 12, 30);
    final pending = PendingPairing(
      link: 'nox://pair/link',
      waitUntil: waitUntil,
      connection: ConnectionSettings(serverAddress: '192.168.1.20:8443', onionAddress: '${'a' * 56}.onion:443', useTor: true),
    );

    test('is remembered whole - the link, the deadline and what was set on the connection screen', () async {
      await repository.savePendingPairing(pending);

      expect((await repository.readPendingPairing()).data, pending);
    });

    test('a link remembered with no connection settings comes back without them', () async {
      await repository.savePendingPairing(PendingPairing(link: 'nox://pair/link', waitUntil: waitUntil));

      final read = (await repository.readPendingPairing()).data!;
      expect(read.connection, isNull);
      expect(read.waitUntil, waitUntil);
    });

    test('lives in secure storage, never in the preferences: the link carries the token', () async {
      await repository.savePendingPairing(pending);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().any((key) => (prefs.get(key)?.toString() ?? '').contains('nox://pair/link')), isFalse);
      expect(await const FlutterSecureStorage().read(key: 'session.pending_pairing'), contains('nox://pair/link'));
    });

    test('nothing remembered reads as none, and so does a value nothing could resume', () async {
      expect((await repository.readPendingPairing()).data, isNull);

      await const FlutterSecureStorage().write(key: 'session.pending_pairing', value: '{not json');
      expect((await repository.readPendingPairing()).data, isNull);
      await const FlutterSecureStorage().write(key: 'session.pending_pairing', value: jsonEncode({'link': 'nox://pair/link'}));
      expect((await repository.readPendingPairing()).data, isNull, reason: 'no deadline, nothing to wait until');
    });

    test('is forgotten when the wait ends', () async {
      await repository.savePendingPairing(pending);
      await repository.clearPendingPairing();

      expect((await repository.readPendingPairing()).data, isNull);
    });

    test('goes with a discarded sign-in, and with a logout', () async {
      await repository.savePendingPairing(pending);
      await repository.discardSignIn();
      expect((await repository.readPendingPairing()).data, isNull);

      await repository.savePendingPairing(pending);
      await repository.clear();
      expect((await repository.readPendingPairing()).data, isNull);
    });
  });

  group('updateLabel (feature 015)', () {
    test('persists the new label and leaves the identifier untouched', () async {
      await repository.saveIdentifier(identifier: 'abc', onboardingComplete: true, label: 'Alice');

      await repository.updateLabel(label: 'Alice2');

      final session = (await repository.readSession()).data!;
      expect(session.label, 'Alice2'); // label persisted
      expect(session.identifier, 'abc'); // identifier rename-invariant (FR-009)
      expect(session.onboardingComplete, isTrue); // flag untouched
    });
  });

  group('watchLabel (feature 015)', () {
    test('emits the current cached label on listen, then the renamed label, then null on clear', () async {
      await repository.saveIdentifier(identifier: 'abc', onboardingComplete: true, label: 'Alice');

      final emitted = <String?>[];
      final sub = repository.watchLabel().listen(emitted.add);
      await Future<void>.delayed(Duration.zero); // let the seed emission land

      expect(emitted, ['Alice']); // seeded with the current value

      await repository.updateLabel(label: 'Zed');
      await repository.clear();
      await Future<void>.delayed(Duration.zero);

      expect(emitted, ['Alice', 'Zed', null]); // current → rename → logout reset
      await sub.cancel();
    });
  });

  test('logout removes the server-assigned author id along with the rest (026)', () async {
    await repository.saveIdentifier(identifier: 'sess-1', onboardingComplete: true, label: 'Anna');
    await repository.adoptServerIdentity(authorId: 'srv-anna', label: 'Anna');
    expect((await repository.readSession()).data?.authorId, 'srv-anna');

    await repository.clear();
    await repository.saveIdentifier(identifier: 'sess-2', onboardingComplete: true);

    // Left behind, the previous identity's author id would mark a stranger's
    // messages as this user's own until the next greeting overwrote it.
    expect((await repository.readSession()).data?.authorId, isNull);
  });

  group('discarding a sign-in and forgetting a world', () {
    // Both survived feature 037 and both had their only coverage deleted with
    // the ownership group they happened to sit in. Their own comments call the
    // consequences severe, and deleting either `remove` would leave the suite
    // green while a stranger's name and author id stayed on screen.
    test('a discarded sign-in leaves neither the author id nor the label behind', () async {
      await repository.saveIdentifier(identifier: 'sess-1', onboardingComplete: true);
      await repository.adoptServerIdentity(authorId: 'u_serverA', label: 'Anna');

      await repository.discardSignIn();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('session.author_id'), isNull, reason: "the next sign-in would mark a stranger's messages as its own");
      expect(prefs.getString('session.label'), isNull, reason: "settings and both avatars would render a stranger's name");
    });

    test('forgetting the world drops the author id, and only that', () async {
      await repository.saveIdentifier(identifier: 'sess-1', onboardingComplete: true);
      await repository.adoptServerIdentity(authorId: 'u_serverA', label: 'Anna');

      await repository.forgetAuthorId();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('session.author_id'), isNull);
      // The session itself is untouched: this is a rebuilt store, not a logout.
      expect((await repository.readSession()).data?.identifier, 'sess-1');
    });
  });

  group('the ownership key left by older builds', () {
    test('the bootstrap sweep drops it, without waiting for a logout', () async {
      // Written by builds that still had an owner badge. Nothing reads it now -
      // this machine belongs to one person - but the install this sweep exists
      // for is one upgraded from such a build, and an install that never signs
      // out never reaches logout.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('session.is_owner', true);
      await repository.saveIdentifier(identifier: 'sess-1', onboardingComplete: true);

      expect((await repository.sweepLegacyKeys()).hasData, isTrue);

      expect(prefs.getBool('session.is_owner'), isNull);
    });

    test('a signed-out install loses it too, where there is no session at all', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('session.is_owner', false);

      expect((await repository.sweepLegacyKeys()).hasData, isTrue);

      expect(prefs.getBool('session.is_owner'), isNull);
    });

    test('a session read migrates nothing', () async {
      // The sweep belongs to bootstrap. Riding it on readSession - the app's
      // hottest repository call - made a read perform a write and put a
      // one-time migration inside the envelope that decides whether a
      // signed-in person lands on their chats or on the Login screen.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('session.is_owner', true);
      await repository.saveIdentifier(identifier: 'sess-1', onboardingComplete: true);

      await repository.readSession();

      expect(prefs.getBool('session.is_owner'), isTrue, reason: 'a read wrote to storage');
    });

    test('sweeping twice is not an error, and neither is sweeping a key that was never there', () async {
      final prefs = await SharedPreferences.getInstance();

      expect((await repository.sweepLegacyKeys()).hasData, isTrue);
      expect((await repository.sweepLegacyKeys()).hasData, isTrue);

      expect(prefs.getBool('session.is_owner'), isNull);
    });
  });

  group('connection records (phases 040, 045)', () {
    const storage = FlutterSecureStorage();

    Future<void> writeSettings() =>
        storage.write(key: ConnectionStorage.serverAddresses, value: '{"direct":["10.0.0.5:8443"],"use_tor":true}');

    /// What builds of phases 040-044 kept: the device's onion access key and
    /// its registration mark.
    Future<void> writeLegacyAccessKey() async {
      await storage.write(key: ConnectionStorage.legacyAccessKeyRegistered, value: '1');
      await storage.write(
        key: ConnectionStorage.legacyAccessKey,
        value: 'BBBB',
        iOptions: ConnectionStorage.legacyKeyIOSOptions,
        mOptions: ConnectionStorage.legacyKeyMacOsOptions,
      );
    }

    test('logout removes the connection settings', () async {
      await repository.saveIdentifier(identifier: 'abc', onboardingComplete: true);
      await writeSettings();
      await repository.clear();
      expect(await storage.read(key: ConnectionStorage.serverAddresses), isNull);
    });

    test('a failed sign-in drops the connection settings it wrote', () async {
      await writeSettings();
      await repository.discardSignIn();
      expect(await storage.read(key: ConnectionStorage.serverAddresses), isNull);
    });

    test('the bootstrap sweep drops the access key of earlier builds and its mark (phase 045)', () async {
      // The onion address opens for no key since phase 045, and nothing reads
      // either record any more.
      await writeLegacyAccessKey();

      expect((await repository.sweepLegacyKeys()).hasData, isTrue);

      expect(await storage.read(key: ConnectionStorage.legacyAccessKeyRegistered), isNull);
      expect(
        await storage.read(
          key: ConnectionStorage.legacyAccessKey,
          iOptions: ConnectionStorage.legacyKeyIOSOptions,
          mOptions: ConnectionStorage.legacyKeyMacOsOptions,
        ),
        isNull,
      );
    });

    test('the bootstrap sweep drops a one-time invite key left by earlier builds', () async {
      // Those builds kept a version-2 invite's key on disk for its pairing, and
      // a pairing the process did not survive left it there; nothing else
      // names it any more (FR-021).
      await storage.write(key: 'session.invite_onion', value: 'abc.onion:443');
      await storage.write(
        key: 'session.invite_access_key',
        value: 'AAAA',
        iOptions: ConnectionStorage.legacyKeyIOSOptions,
        mOptions: ConnectionStorage.legacyKeyMacOsOptions,
      );

      expect((await repository.sweepLegacyKeys()).hasData, isTrue);

      expect(await storage.read(key: 'session.invite_onion'), isNull);
      expect(await storage.read(key: 'session.invite_access_key'), isNull);
    });

    test('a new server starts with nothing an earlier one said about itself', () async {
      // A sign-in the process did not survive leaves the old server's records
      // behind; kept, they would send the next connection to its addresses.
      await writeSettings();
      await repository.saveServer(address: '10.0.0.9:8443', serverKey: 'oJql9HpnWYAv+VX43C0qFKXJnSO+l/hkEn/5ODRVpPA=');
      expect(await storage.read(key: ConnectionStorage.serverAddresses), isNull);
      expect((await repository.serverAddress()).data, '10.0.0.9:8443');
    });
  });
}

/// Secure storage whose `deleteAll` is a no-op - the macOS behaviour that made
/// the wipe partial. Everything else goes to the real mock platform.
class _NoSweepStorage extends FlutterSecureStorage {
  const _NoSweepStorage();

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {}
}

/// A keychain that is still locked after a reboot: every read throws.
class _LockedStorage extends FlutterSecureStorage {
  const _LockedStorage();

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw StateError('the keychain is locked');
}

/// The worse store: neither the sweep nor a delete of the identifier lands, so
/// the wipe genuinely cannot happen and `clear` has to say so.
class _UndeletableIdentityStorage extends _NoSweepStorage {
  const _UndeletableIdentityStorage();

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (key == 'session.identifier') return;
    await super.delete(key: key);
  }
}
