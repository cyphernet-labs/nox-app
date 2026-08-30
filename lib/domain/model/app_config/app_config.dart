import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';

/// Flavor-dependent runtime config. Carries the flavor and a nullable [apiUrl]
/// (`null` means no real requests are built this phase — the contract-v0 endpoint
/// lands with the transport, feature 027). The token source is wired via
/// [AppConfigRepository] (stage-2 auth; stage 1 runs without it).
class AppConfig {
  const AppConfig({required this.flavor, this.apiUrl});

  final AppFlavorType flavor;

  /// Base URL of the client server. `null` while the app runs on mocks → the
  /// transport stays inert (everything is served from the local Sembast DB). The
  /// per-flavor real URL lands with the WebSocket transport (phase 027);
  /// feature S5 wired only the plumbing.
  final String? apiUrl;
}
