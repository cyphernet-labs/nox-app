import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nox_app/data/local/secure/secure_storage_delete.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/data/repository/connection/connection_storage.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/app/session_model.dart';
import 'package:nox_app/domain/model/connection/connection_settings.dart';
import 'package:nox_app/domain/model/session/pending_pairing.dart';
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

  /// Written by builds that still had an owner badge. Nothing reads it any
  /// more — this machine belongs to one person, so the answer was the same on
  /// every server that ever ran.
  ///
  /// Swept at bootstrap rather than at logout: the install this exists for is
  /// one upgraded from such a build, and an install that never signs out never
  /// reaches logout.
  static const String _kLegacyIsOwner = 'session.is_owner';

  /// A version-2 invite's onion address and one-time key, as earlier builds of
  /// phase 040 stored them; a pairing the process did not survive left them
  /// behind. Links carry no such key any more (phase 044).
  static const String _kLegacyInviteOnion = 'session.invite_onion';
  static const String _kLegacyInviteAccessKey = 'session.invite_access_key';

  /// This device's Ed25519 seed. The private half of the pair whose public
  /// half the server knows as `device_key` — it is generated here, stays here,
  /// and dies with a logout through `deleteAll`.
  static const String _kDeviceSecret = 'session.device_secret';

  /// Where this install's connection to its server starts, and the server's
  /// Ed25519 key (base64) every connection must prove (phase 044). Both come
  /// out of the pairing link.
  ///
  /// They belong to the SESSION, not to the build: they say which server this
  /// installation belongs to, and they die with it. Keeping the address in a
  /// compile-time config instead would mean pairing with one server and
  /// sending messages to another.
  static const String _kServerAddress = 'session.server_address';
  static const String _kServerKey = 'session.server_key';

  /// The fingerprint of the certificate key the builds before phase 044
  /// pinned against. Nothing reads it any more: the session it belonged to is
  /// wiped at the first launch (FR-025).
  static const String _kLegacyServerFingerprint = 'session.server_fingerprint';

  /// A pairing waiting for approval on another device (phase 046): the link,
  /// what was set on the connection screen and this device's deadline, as one
  /// JSON value. Secure storage, because the link carries the token.
  static const String _kPendingPairing = 'session.pending_pairing';

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
  Future<RepositoryResult<bool>> sweepLegacyKeys() {
    // Inside `execute`, which logs and never throws, so bootstrap needs no
    // guard of its own and a refusing storage cannot stop the app from opening.
    return execute<bool>(() async {
      if (_prefs.containsKey(_kLegacyIsOwner)) await _prefs.remove(_kLegacyIsOwner);
      await _secureStorage.deleteIfPresent(key: _kLegacyInviteOnion);
      await _secureStorage.deleteIfPresent(key: _kLegacyServerFingerprint);
      await _secureStorage.deleteIfPresent(
        key: _kLegacyInviteAccessKey,
        iOptions: ConnectionStorage.legacyKeyIOSOptions,
        mOptions: ConnectionStorage.legacyKeyMacOsOptions,
      );
      // The device's onion access key and its registration mark (phases
      // 040-044): the onion service opens for no key since phase 045.
      await ConnectionStorage.sweepLegacy(_secureStorage);
      return const RepositoryResult<bool>.success(data: true);
    });
  }

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
      // What any earlier server said about itself goes first (phase 040): its
      // addresses, and what the person set for it. A sign-in the process did
      // not survive leaves them behind, and kept they would send the next
      // server's connection to the old one's addresses.
      await ConnectionStorage.delete(_secureStorage);
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
  Future<RepositoryResult<String?>> serverKey() {
    return execute<String?>(() async {
      final stored = await _secureStorage.read(key: _kServerKey);
      return RepositoryResult<String?>.success(data: (stored?.isEmpty ?? true) ? null : stored);
    });
  }

  @override
  Future<RepositoryResult<bool>> predatesServerKey() {
    // Inside `execute`: a read that throws comes back as an error, and the
    // caller wipes nothing on an error.
    return execute<bool>(() async {
      final identifier = await _secureStorage.read(key: _kIdentifier);
      if (identifier == null || identifier.isEmpty) return const RepositoryResult<bool>.success(data: false);
      final key = await _secureStorage.read(key: _kServerKey);
      return RepositoryResult<bool>.success(data: key == null || key.isEmpty);
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
  Future<RepositoryResult<bool>> savePendingPairing(PendingPairing pairing) {
    return execute<bool>(() async {
      final connection = pairing.connection;
      await _secureStorage.write(
        key: _kPendingPairing,
        value: jsonEncode(<String, dynamic>{
          'link': pairing.link,
          'wait_until': pairing.waitUntil.toUtc().millisecondsSinceEpoch,
          if (connection != null)
            'connection': <String, dynamic>{
              'server_address': connection.serverAddress,
              'onion_address': ?connection.onionAddress,
              'use_tor': connection.useTor,
            },
        }),
      );
      return const RepositoryResult<bool>.success(data: true);
    });
  }

  @override
  Future<RepositoryResult<PendingPairing?>> readPendingPairing() {
    return execute<PendingPairing?>(() async {
      final stored = await _secureStorage.read(key: _kPendingPairing);
      return RepositoryResult<PendingPairing?>.success(data: stored == null ? null : _pendingFrom(stored));
    });
  }

  @override
  Future<RepositoryResult<bool>> clearPendingPairing() {
    return execute<bool>(() async {
      await _secureStorage.deleteIfPresent(key: _kPendingPairing);
      return const RepositoryResult<bool>.success(data: true);
    });
  }

  /// A remembered pairing, or null for anything that does not read as one -
  /// a value nothing can resume is the same as no value.
  static PendingPairing? _pendingFrom(String stored) {
    try {
      final json = jsonDecode(stored);
      if (json is! Map<String, dynamic>) return null;
      final link = json['link'];
      final until = json['wait_until'];
      if (link is! String || link.isEmpty || until is! int) return null;
      final raw = json['connection'];
      final connection = raw is Map<String, dynamic> && raw['server_address'] is String
          ? ConnectionSettings(
              serverAddress: raw['server_address'] as String,
              onionAddress: raw['onion_address'] is String ? raw['onion_address'] as String : null,
              useTor: raw['use_tor'] == true,
            )
          : null;
      return PendingPairing(link: link, waitUntil: DateTime.fromMillisecondsSinceEpoch(until, isUtc: true), connection: connection);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<RepositoryResult<bool>> discardSignIn() {
    return execute<bool>(() async {
      // Deliberately narrower than [clear]: it removes exactly what a sign-in
      // wrote and leaves the device id alone. That id names this install, not
      // the person, so an attempt that never reached the server must not
      // rotate it - doing so would make one install look like two devices to
      // the server the moment the next attempt succeeds.
      _onboardingStartedHere = false;
      await _secureStorage.deleteIfPresent(key: _kIdentifier);
      // The server the failed attempt pointed at goes with it. Leaving it would
      // aim the next connection at a machine this install never paired with,
      // and the world-epoch key would call that the same world.
      await _secureStorage.deleteIfPresent(key: _kServerAddress);
      await _secureStorage.deleteIfPresent(key: _kServerKey);
      // And what that server said about where it lives, with what the person
      // set for it on the connection screen (phases 040, 045).
      await ConnectionStorage.delete(_secureStorage);
      // And the wait for approval that attempt left (phase 046): it names the
      // link, a credential, and a restart must not resume a sign-in that was
      // undone.
      await _secureStorage.deleteIfPresent(key: _kPendingPairing);
      await _prefs.remove(_kOnboardingComplete);
      // And the author id written by the SAME call. Left behind it would point
      // at the previous server's person, and the next sign-in would inherit it
      // and mark that stranger's messages as its own - the hazard clear() names
      // in its own comment, reachable here since sign-in started adopting the
      // identity from the pair reply.
      await _prefs.remove(_kAuthorId);
      // And the label written by that same call. Left behind, it is the failed
      // server's person's name, and the pairing path's next saveIdentifier
      // states none - so Settings and both account avatars would render a
      // stranger's name until some greeting happened to overwrite it.
      await _prefs.remove(_kLabel);
      // Live listeners are told, exactly as clear() tells them. Without this a
      // mounted surface keeps rendering values the storage no longer holds.
      _emitLabel(null);
      return const RepositoryResult<bool>.success(data: true);
    });
  }

  @override
  Future<RepositoryResult<bool>> clear() {
    return execute<bool>(() async {
      _onboardingStartedHere = false;
      // Every key BY NAME, and only then the sweep. `deleteAll` alone is not a
      // wipe: it is one query against the platform store, and a key written
      // under options that query does not match survives it - silently, with no
      // error to catch. What that produces is worse than no wipe at all,
      // because the two halves of a session live in different stores: the
      // identifier stays in secure storage while the prefs below go, and
      // readSession then reports a person who has not finished onboarding. The
      // app puts them on the naming screen, holding a token for a server it can
      // no longer reach.
      await _secureStorage.deleteIfPresent(key: _kIdentifier);
      await _secureStorage.deleteIfPresent(key: _kDeviceSecret);
      await _secureStorage.deleteIfPresent(key: _kServerAddress);
      await _secureStorage.deleteIfPresent(key: _kServerKey);
      await _secureStorage.deleteIfPresent(key: _kLegacyServerFingerprint);
      await _secureStorage.deleteIfPresent(key: _kPendingPairing);
      // The connection settings (phases 040, 045), by name like the rest.
      await ConnectionStorage.delete(_secureStorage);
      // Kept for anything a later version writes and forgets to name above, and
      // not allowed to fail a wipe that has already happened.
      // Swallowed on purpose, and it is not a silent failure: the read-back
      // below decides whether the wipe happened, which is a stronger answer
      // than whether the sweep threw.
      try {
        await _secureStorage.deleteAll();
      } on Object {
        // ignored - see above
      }
      // Read back before touching the prefs. Presence is keyed on the
      // identifier, so an identifier that survived is the whole session; the
      // prefs are what turn that survival into the stranded state above.
      // Leaving them alone means a failed wipe leaves the person signed in -
      // reported, recoverable, and refused by the caller - instead of signed
      // out into a screen that leads nowhere.
      final survivor = await _secureStorage.read(key: _kIdentifier);
      if (survivor != null && survivor.isNotEmpty) {
        return const RepositoryResult<bool>.error(exception: RepositoryException.unknown);
      }
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
