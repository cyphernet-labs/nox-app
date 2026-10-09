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
  /// `logout(forced: true)` has exactly two owners during a session (FR-013): the
  /// server answering `session.hello` with `unauthenticated`, and this device's
  /// revocation from another. Nothing about the channel - another server's key, a
  /// failed open, a 401 on a file transfer - ever reaches it.
  Future<RepositoryResult<bool>> logout({bool forced = false});

  /// Retires a session paired before phase 044 - an identifier with no server
  /// key (FR-025): one forced logout through [logout], the full wipe, and the
  /// pairing screen. Nothing it holds could check a connection, and the
  /// server it paired with is gone with its old database. Once: the wipe
  /// leaves no identifier behind.
  ///
  /// A storage READ error retires nothing - a keychain still locked after a
  /// reboot is not proof of anything. Called at bootstrap; `true` when it
  /// retired a session.
  Future<RepositoryResult<bool>> retireLegacySession();
}
