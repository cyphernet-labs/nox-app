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
    @Default(false) bool onboardingComplete,
  }) = _SessionModel;
}
