import 'package:flutter/material.dart';
import 'package:nox_app/design/theme/app_colors.dart';

/// Minimal Material 3 light/dark theme, seeded from the NOX teal, with the
/// AppColors extension registered. US4 replaces the seed/palette with the
/// generated nox-handoff design tokens.
class AppTheme {
  static const Color _seed = Color(0xFF0E8A8A); // placeholder teal; real value from nox-handoff (US4)

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.light),
      extensions: const <ThemeExtension<dynamic>>[LightAppColors()],
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
      extensions: const <ThemeExtension<dynamic>>[DarkAppColors()],
    );
  }
}
