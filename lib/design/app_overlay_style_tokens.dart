import 'package:flutter/services.dart';

/// System UI overlay (status bar) styles per brightness. Nav-bar fields are
/// intentionally omitted (Android-only; NOX targets five platforms).
abstract final class AppOverlayStyleTokens {
  const AppOverlayStyleTokens._();

  static const SystemUiOverlayStyle light = SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  );

  static const SystemUiOverlayStyle dark = SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  );
}
