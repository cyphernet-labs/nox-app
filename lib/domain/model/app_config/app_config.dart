import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';

/// Flavor-dependent runtime config. Carries the flavor and a nullable [apiUrl]
/// (example/TBD — backend/protocol not chosen; `null` means no real requests are
/// built this phase). Security headers / token source are wired via
/// [AppConfigRepository], also TBD until the NOX backend is chosen.
class AppConfig {
  const AppConfig({required this.flavor, this.apiUrl});

  final AppFlavorType flavor;

  /// Base URL for the (future) backend. `null` = TBD placeholder → the transport
  /// stays inert (the app runs on the local Sembast DB). A per-flavor real URL lands
  /// with the backend (feature S5 wires only the plumbing).
  final String? apiUrl;
}
