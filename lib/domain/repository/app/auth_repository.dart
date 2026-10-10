import 'package:nox_app/domain/model/connection/connection_settings.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

/// Orchestrates session mutations on the "mutate source-of-truth → fetchAppState()"
/// contract. The single home of the logout path, and of sign-in by a pairing
/// link.
abstract class AuthRepository {
  /// Pairs this device by the pairing link [identifier], then re-derives app
  /// state. [connection] is what the person confirmed on the connection
  /// screen (phase 045): the server address and onion address - stored as
  /// hand edits where they differ from the link's - and `Use Tor`, which
  /// decides whether the pairing itself may go through Tor. Without it the
  /// link's own addresses are used, with Tor off.
  Future<RepositoryResult<bool>> signIn({required String identifier, ConnectionSettings? connection});

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
