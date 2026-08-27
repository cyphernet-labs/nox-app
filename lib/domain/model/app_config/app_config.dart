import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';

/// Flavor-dependent runtime config. Carries the flavor and a nullable [apiUrl]
/// (`null` means no real requests are built this phase — the contract-v0 endpoint
/// lands with the transport, feature 027). The token source is wired via
/// [AppConfigRepository] (stage-2 auth; stage 1 runs without it).
class AppConfig {
  const AppConfig({required this.flavor, this.apiUrl});

  final AppFlavorType flavor;

  /// Base URL for the (future) backend. `null` = TBD placeholder → the transport
  /// stays inert (the app runs on the local Sembast DB). A per-flavor real URL lands
  /// with the backend (feature S5 wires only the plumbing).
  final String? apiUrl;
}
