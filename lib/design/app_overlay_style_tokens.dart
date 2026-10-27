import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// System UI overlay styles. [of] is what every screen carries - `AppRoot` puts
/// it under the whole app, an AppBar sets its own status bar over it - and
/// [splash] is brand-fixed like the splash itself.
abstract final class AppOverlayStyleTokens {
  const AppOverlayStyleTokens._();

  /// The theme's style: a transparent status bar with icons that read on the
  /// theme, and an Android navigation bar in the colour of the bottom bar
  /// (`surfaceContainer`) with icons that read on it. The navigation bar is set
  /// on purpose: the splash darkens it, and nothing else would bring it back.
  static SystemUiOverlayStyle of(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: const Color(0x00000000),
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: scheme.surfaceContainer,
      systemNavigationBarDividerColor: const Color(0x00000000),
      systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    );
  }

  /// Always dark, with a transparent navigation bar over the dark canvas.
  static const SystemUiOverlayStyle splash = SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    systemNavigationBarColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.light,
  );
}
