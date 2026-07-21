import 'package:nox_app/domain/model/app/session_model.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

/// Cache-only session store. `identifier` lives in secure storage; the
/// `onboardingComplete` flag and cached `label` in shared_preferences.
abstract class SessionRepository {
  /// Reads the session from cache (no network). `data == null` ⇒ no session.
  Future<RepositoryResult<SessionModel?>> readSession();

  /// Persists the identifier (secure storage) + onboarding flag / label (prefs).
  Future<RepositoryResult<bool>> saveIdentifier({required String identifier, required bool onboardingComplete, String? label});

  /// Marks first-login onboarding complete (+ optionally caches the label).
  Future<RepositoryResult<bool>> setOnboardingComplete({String? label});

  /// Persists a new display label (non-secret prefs) and broadcasts it on [watchLabel].
  /// Does NOT touch the secure identifier. Caller guarantees the label already passed
  /// validation (charset / uniqueness / ≤32).
  Future<RepositoryResult<bool>> updateLabel({required String label});

  /// Reactive display-label signal: emits the current cached label on listen, then
  /// every subsequent change (rename → new label, logout/clear → null). Broadcast —
  /// multiple surfaces (shell avatar, future consumers) may listen concurrently.
  Stream<String?> watchLabel();

  /// Full wipe: secure storage deleteAll + remove prefs keys (logout).
  Future<RepositoryResult<bool>> clear();
}
