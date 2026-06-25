import 'package:nox_app/domain/repository/base/repository_result.dart';

/// Orchestrates session mutations on the "mutate source-of-truth → fetchAppState()"
/// contract. The single home of the logout path; future home of real sign-in
/// (backend TBD). Sign-in is currently stubbed (no client-side validation).
abstract class AuthRepository {
  /// Stub sign-in: persists the identifier, then re-derives app state.
  Future<RepositoryResult<bool>> signIn({required String identifier});

  /// First-login completion (Set username 2.3): marks onboarding complete, re-derives.
  Future<RepositoryResult<bool>> completeOnboarding({String? label});

  /// Single logout path. Only [forced] sets the one-shot `sessionExpired` flag.
  /// `forceLogout` == `logout(forced: true)` (programmatic/dev; 401 trigger deferred).
  Future<RepositoryResult<bool>> logout({bool forced = false});
}
