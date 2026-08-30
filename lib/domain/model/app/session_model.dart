import 'package:freezed_annotation/freezed_annotation.dart';

part 'session_model.freezed.dart';

/// Cache-only session aggregate — the single input to the app-state resolver.
/// `identifier` is security-sensitive (secure storage); `label`/`onboardingComplete`
/// are non-secret (shared_preferences). `onboardingComplete` discriminates
/// `registrationPending` vs `authorized`. Replaces the migrated `UserModel`.
@freezed
abstract class SessionModel with _$SessionModel {
  const factory SessionModel({
    required String identifier,
    String? label,

    /// The author id the SERVER assigns at greeting time (contract §3).
    ///
    /// Distinct from [identifier], which is how this device signs in: the
    /// server stamps every message with ITS id, so own-vs-other detection has
    /// to compare against this one. Null while the app runs on mocks, where the
    /// login identifier is the only id there is.
    String? authorId,
    @Default(false) bool onboardingComplete,
  }) = _SessionModel;
}
