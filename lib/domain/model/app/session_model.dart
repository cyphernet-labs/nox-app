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

    /// Whether this person owns the server they are paired with (contract §3).
    ///
    /// Same name as `ServerIdentity.isOwner` on purpose: one fact deserves one
    /// name, and two names for it is how a copy between them goes wrong.
    ///
    /// Null means "the server has never said" — a fresh install, or an older
    /// server. Rendering that as "not the owner" would show the owner a wrong
    /// answer on every offline launch, so the badge stays absent for both and
    /// the difference lives here rather than in the widget.
    bool? isOwner,
    @Default(false) bool onboardingComplete,
  }) = _SessionModel;
}
