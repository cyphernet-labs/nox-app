import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/domain/model/app/session_model.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
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
      await _prefs.setBool(_kOnboardingComplete, true);
      if (label != null) await _prefs.setString(_kLabel, label);
      if (label != null) _emitLabel(label);
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
  Future<RepositoryResult<bool>> clear() {
    return execute<bool>(() async {
      await _secureStorage.deleteAll();
      await _prefs.remove(_kOnboardingComplete);
      await _prefs.remove(_kLabel);
      _emitLabel(null); // logout resets every label surface to the fallback
      return const RepositoryResult<bool>.success(data: true);
    });
  }
}
