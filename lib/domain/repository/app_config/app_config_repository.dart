import 'package:nox_app/domain/model/app_config/app_config.dart';
import 'package:nox_app/domain/model/app_config/server_limits.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';

/// Holds flavor-dependent config, initialized once after the DI container is ready
/// (see contracts/di-bootstrap.md), plus the auth-token source for the transport
/// seam. `apiUrl` carries the server address from feature 026; the token writer is
/// stage-2 auth and does not exist yet.
abstract class AppConfigRepository {
  Future<void> initialize({required AppFlavorType flavorType});

  AppConfig get config;

  /// The signed-in user's auth token for the `Authorization` header. Read from secure
  /// storage (key `auth_id_token`); `null`/empty in the mock phase (no writer yet — the
  /// stage-2 sign-in will persist it; stage 1 of the contract runs without auth).
  Future<String?> getUserAuthIdToken();

  /// Server payload bounds from the last session.hello (contract §3), the
  /// preflight seam for the composer/picker. Contract defaults until a live
  /// handshake lands via [updateLimits] — which is every mock-backed flavor, and
  /// the window before the first greeting on a live one.
  ServerLimits get limits;

  /// Stores the limits of a live handshake. Written by `LiveSessionStarter` on
  /// every greeting (feature 026) — the server may revise them at any reconnect.
  void updateLimits(ServerLimits limits);

  /// True under the test environment — the future hook for bypassing real auth in tests.
  /// Wired now (env-keyed); its consumers arrive with the backend.
  bool get isTestEnvironment;
}
