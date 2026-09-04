import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/domain/model/app/session_model.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/general/pairing/device_keys.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Security-sensitive identifier → secure storage; non-secret onboarding flag and
/// cached label → shared_preferences. Full wipe = deleteAll + remove prefs keys.
@LazySingleton(as: SessionRepository, env: [Environment.dev, Environment.prod, Environment.test])
class SessionRepositoryImpl with BaseRepositoryHelper implements SessionRepository {
  SessionRepositoryImpl(this._secureStorage, this._prefs);

  final FlutterSecureStorage _secureStorage;
  final SharedPreferences _prefs;

  static const String _kIdentifier = 'session.identifier';
  static const String _kOnboardingComplete = 'session.onboarding_complete';
  static const String _kLabel = 'session.label';

  // Broadcast label change-signal (feature 015). A rename / onboarding label write
  // emits the new label; clear (logout) emits null. Broadcast so N surfaces (shell
  // avatar, future consumers) can listen. Never closed — a lazy singleton lives for
  // the app; a broadcast controller with no listeners is harmless.
  final StreamController<String?> _labelController = StreamController<String?>.broadcast();

  void _emitLabel(String? label) => _labelController.add(label);

  /// The author id the server assigned; open data, so prefs rather than the
  /// keychain — the login identifier is the secret, this is not.
  static const String _kAuthorId = 'session.author_id';

  /// This device's Ed25519 seed. The private half of the pair whose public
  /// half the server knows as `device_key` — it is generated here, stays here,
  /// and dies with a logout through `deleteAll`.
  static const String _kDeviceSecret = 'session.device_secret';

  /// Where this install's server lives, and the key it will be pinned against
  /// once the transport is TLS. Both come out of the pairing link.
  ///
  /// They belong to the SESSION, not to the build: they say which server this
  /// installation belongs to, and they die with it. Keeping the address in a
  /// compile-time config instead would mean pairing with one server and
  /// sending messages to another.
  static const String _kServerAddress = 'session.server_address';
  static const String _kServerKey = 'session.server_key';

  /// True while THIS process is the one that brought the person into being and
  /// has not finished naming them.
  ///
  /// In memory on purpose. Its only job is to tell "the server made this person
  /// a moment ago, on this device, and someone is typing a name right now"
  /// apart from "this person existed before this install ever greeted" — and
  /// the two are indistinguishable on the wire, because every greeting after
  /// the first reports `created == false` either way. It must NOT survive a
  /// restart: after one, the naming screen is exactly where a greeting SHOULD
  /// rescue a device from.
  bool _onboardingStartedHere = false;

  @override
  Future<RepositoryResult<SessionModel?>> readSession() {
    return execute<SessionModel?>(() async {
      final identifier = await _secureStorage.read(key: _kIdentifier);
      if (identifier == null || identifier.isEmpty) {
        return const RepositoryResult<SessionModel?>.success(data: null);
      }
      return RepositoryResult<SessionModel?>.success(
        data: SessionModel(
          identifier: identifier,
          label: _prefs.getString(_kLabel),
          authorId: _prefs.getString(_kAuthorId),
          onboardingComplete: _prefs.getBool(_kOnboardingComplete) ?? false,
        ),
      );
    });
  }

  @override
  Future<RepositoryResult<bool>> saveIdentifier({required String identifier, required bool onboardingComplete, String? label}) {
    return execute<bool>(() async {
      // Write the non-secret prefs (flag/label) FIRST and the secure identifier LAST:
      // readSession() keys presence on the identifier, so it is the commit point. A
      // crash between the two stores then leaves at worst (flag set, no identifier) →
      // resolves to unauthorized (re-login), never (identifier present, flag absent)
      // which would drop a registered user back onto 2.3 Set username.
      await _prefs.setBool(_kOnboardingComplete, onboardingComplete);
      if (label != null) await _prefs.setString(_kLabel, label);
      await _secureStorage.write(key: _kIdentifier, value: identifier);
      if (label != null) _emitLabel(label);
      return const RepositoryResult<bool>.success(data: true);
    });
  }

  @override
  Future<RepositoryResult<bool>> setOnboardingComplete({String? label}) {
    return execute<bool>(() async {
      // Named (or skipped): this process is no longer the one mid-onboarding,
      // so a later greeting may act on what the server says again.
      _onboardingStartedHere = false;
      await _prefs.setBool(_kOnboardingComplete, true);
      if (label != null) {
        await _prefs.setString(_kLabel, label);
        _emitLabel(label);
      }
      return const RepositoryResult<bool>.success(data: true);
    });
  }

  @override
  Future<RepositoryResult<bool>> adoptServerIdentity({required String authorId, required String label}) {
    return execute<bool>(() async {
      await _prefs.setString(_kAuthorId, authorId);
      final cached = _prefs.getString(_kLabel);
      final changed = cached != label;
      if (changed) {
        await _prefs.setString(_kLabel, label);
        // Only announce a real change: a reconnect that confirms the current
        // name should not ripple through every surface that renders it.
        _emitLabel(label);
      }
      return const RepositoryResult<bool>.success(data: true);
    });
  }

  @override
  Future<RepositoryResult<bool>> updateLabel({required String label}) {
    return execute<bool>(() async {
      // Label only — the secure identifier is rename-invariant (FR-009).
      await _prefs.setString(_kLabel, label);
      _emitLabel(label);
      return const RepositoryResult<bool>.success(data: true);
    });
  }

  @override
  Stream<String?> watchLabel() async* {
    // Seed the current cached label so every new listener starts with the present
    // value, then merge live changes (same shape as the cache-first watchChats).
    yield _prefs.getString(_kLabel);
    yield* _labelController.stream;
  }

  @override
  Future<RepositoryResult<String>> deviceSecret() {
    return execute<String>(() async {
      final stored = await _secureStorage.read(key: _kDeviceSecret);
      if (stored != null && stored.isNotEmpty) {
        return RepositoryResult<String>.success(data: stored);
      }
      // Minted once, on the way into the first pairing. A rotated seed is a
      // device the server no longer knows, which reads as a revocation.
      final minted = await DeviceKeys.generateSeed();
      await _secureStorage.write(key: _kDeviceSecret, value: minted);
      return RepositoryResult<String>.success(data: minted);
    });
  }

  @override
  Future<RepositoryResult<bool>> saveServer({required String address, required String serverKey}) {
    return execute<bool>(() async {
      await _secureStorage.write(key: _kServerAddress, value: address);
      await _secureStorage.write(key: _kServerKey, value: serverKey);
      return const RepositoryResult<bool>.success(data: true);
    });
  }

  @override
  Future<RepositoryResult<String?>> serverAddress() {
    return execute<String?>(() async {
      final stored = await _secureStorage.read(key: _kServerAddress);
      return RepositoryResult<String?>.success(data: (stored?.isEmpty ?? true) ? null : stored);
    });
  }

  @override
  Future<RepositoryResult<bool>> advanceOnboardingIfKnown({required bool created}) {
    return execute<bool>(() async {
      // Forward only. A reconnect that happens BEFORE the person has named
      // themselves legitimately reports created == false, because the row was
      // already made by the first greeting - so "re-derive from every
      // greeting" would silently declare them onboarded under the
      // server-assigned name. Advancing but never retreating is safe in both
      // directions.
      if (created) return const RepositoryResult<bool>.success(data: false);
      // A reconnect while the person is still typing their name reports
      // created == false, because the first greeting already made the row.
      // Advancing on it would swap the root route out from under them and
      // discard what they had typed, under the server-assigned name.
      if (_onboardingStartedHere) return const RepositoryResult<bool>.success(data: false);
      if (_prefs.getBool(_kOnboardingComplete) ?? false) {
        return const RepositoryResult<bool>.success(data: false);
      }
      await _prefs.setBool(_kOnboardingComplete, true);
      return const RepositoryResult<bool>.success(data: true);
    });
  }

  @override
  Future<RepositoryResult<bool>> forgetAuthorId() {
    return execute<bool>(() async {
      await _prefs.remove(_kAuthorId);
      return const RepositoryResult<bool>.success(data: true);
    });
  }

  @override
  void noteOnboardingStartedHere() => _onboardingStartedHere = true;

  @override
  Future<RepositoryResult<bool>> discardSignIn() {
    return execute<bool>(() async {
      // Deliberately narrower than [clear]: it removes exactly what a sign-in
      // wrote and leaves the device id alone. That id names this install, not
      // the person, so an attempt that never reached the server must not
      // rotate it - doing so would make one install look like two devices to
      // the server the moment the next attempt succeeds.
      _onboardingStartedHere = false;
      await _secureStorage.delete(key: _kIdentifier);
      await _prefs.remove(_kOnboardingComplete);
      return const RepositoryResult<bool>.success(data: true);
    });
  }

  @override
  Future<RepositoryResult<bool>> clear() {
    return execute<bool>(() async {
      _onboardingStartedHere = false;
      await _secureStorage.deleteAll();
      await _prefs.remove(_kOnboardingComplete);
      await _prefs.remove(_kLabel);
      // The server-assigned author id belongs to the identity being logged out.
      // Leaving it behind would let the next sign-in inherit it and mark that
      // stranger's messages as its own until the next greeting overwrote it.
      await _prefs.remove(_kAuthorId);
      _emitLabel(null); // logout resets every label surface to the fallback
      return const RepositoryResult<bool>.success(data: true);
    });
  }
}
