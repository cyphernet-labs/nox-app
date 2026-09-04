import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/repository/app/session_repository_impl.dart';
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

  group('the paired server (feature 032)', () {
    test('address and key survive, so the app talks to the server it paired with', () async {
      await repository.saveServer(address: '10.0.0.5:9000', serverKey: 'A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=');

      expect((await repository.serverAddress()).data, '10.0.0.5:9000');
    });

    test('an install that never paired has no address', () async {
      expect((await repository.serverAddress()).data, isNull);
    });

    test('logout forgets the server, because the next link brings its own', () async {
      await repository.saveServer(address: '10.0.0.5:9000', serverKey: 'A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=');
      await repository.clear();

      expect((await repository.serverAddress()).data, isNull);
    });

    test('the device seed is a real 32-byte key, not a random string', () async {
      final seed = (await repository.deviceSecret()).data!;
      // If this ever stops being a key, signing silently starts throwing and
      // every connection fails with an error nobody can trace to here.
      expect(base64.decode(seed).length, 32);
      expect((await DeviceKeys.publicKey(seed)).isNotEmpty, isTrue);
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
}
