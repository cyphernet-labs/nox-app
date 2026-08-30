import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';

/// Resolves the compile-time flavor from `--dart-define=app.flavor=<flavor>`
/// (mobile) or `--dart-define-from-file=config/<flavor>.json` (desktop).
/// Empty/unknown -> prod (safe default). No runtime branching by flavor.
class AppFlavor {
  AppFlavor._();

  static AppFlavorType getFlavor() {
    const raw = String.fromEnvironment('app.flavor');
    return switch (raw) {
      'stage' => AppFlavorType.stage,
      'prod' => AppFlavorType.prod,
      _ => AppFlavorType.prod,
    };
  }

  /// Base URL of the client server, from `--dart-define=app.apiUrl=<url>`.
  ///
  /// Empty means "no server": the app keeps serving mock data and the transport
  /// never opens a socket. Only the stage flavor ships a value today.
  static String? getApiUrl() {
    const raw = String.fromEnvironment('app.apiUrl');
    return raw.isEmpty ? null : raw;
  }
}
