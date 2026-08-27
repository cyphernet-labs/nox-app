import 'package:nox_app/domain/model/app_config/app_config.dart';
import 'package:nox_app/domain/model/app_config/server_limits.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';

/// Holds flavor-dependent config, initialized once after the DI container is ready
/// (see contracts/di-bootstrap.md), plus the auth-token source for the transport
/// seam. `apiUrl` / token are example/TBD until the NOX backend is chosen (feature S5).
abstract class AppConfigRepository {
  Future<void> initialize({required AppFlavorType flavorType});

  AppConfig get config;

  /// The signed-in user's auth token for the `Authorization` header. Read from secure
  /// storage (key `auth_id_token`); `null`/empty in the mock phase (no writer yet — a
  /// real sign-in will persist it). Example/TBD scheme (bearer) until the backend is chosen.
  Future<String?> getUserAuthIdToken();

  /// Server payload bounds from the last session.hello (contract §3), the
  /// preflight seam for the composer/picker. Contract defaults until the
  /// transport (027) stores a live handshake via [updateLimits].
  ServerLimits get limits;

  /// Stores the limits of a live handshake (writer arrives with phase 027).
  void updateLimits(ServerLimits limits);

  /// True under the test environment — the future hook for bypassing real auth in tests.
  /// Wired now (env-keyed); its consumers arrive with the backend.
  bool get isTestEnvironment;
}
