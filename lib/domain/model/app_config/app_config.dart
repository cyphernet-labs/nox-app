import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';

/// Flavor-dependent runtime config. Carries the flavor and a nullable [apiUrl]
/// (`null` means this build has no server address and stays on the local cache).
/// The token source is wired via [AppConfigRepository] (stage-2 auth; stage 1 of
/// the contract runs without it).
class AppConfig {
  const AppConfig({required this.flavor, this.apiUrl});

  final AppFlavorType flavor;

  /// Base URL of the client server, from `--dart-define=app.apiUrl`. The stage
  /// flavor (which boots `Environment.dev`) carries the local `noxd` address
  /// since feature 026; prod ships none and stays on the cache.
  ///
  /// It feeds the WEBSOCKET url the live channel derives from it, not Dio: the
  /// contract's commands travel over the envelope, and `ApiClient` stays inert
  /// until the blob chain (phase 028) gives it something to fetch.
  final String? apiUrl;
}
