import 'package:flutter/material.dart';
import 'package:nox_app/design/theme/app_colors.dart';
import 'package:nox_app/design/theme/nox_color_scheme.dart';
import 'package:nox_app/design/theme/nox_text_theme.dart';

/// NOX Material 3 theme. The `ColorScheme` and `TextTheme` come from the
/// token-generated design-system handoff (`lib/design/theme/nox_*.dart`,
/// regenerated from `docs/design/system/nox-handoff/tokens` — never hand-edited),
/// so the palette is the hand-tuned NOX teal scheme, not a raw `fromSeed`.
/// Semantic, mode-dependent extras ride along via the AppColors ThemeExtension.
class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(noxLightScheme, const LightAppColors());

  static ThemeData dark() => _build(noxDarkScheme, const DarkAppColors());

  static ThemeData _build(ColorScheme scheme, AppColors appColors) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: noxTextTheme,
      scaffoldBackgroundColor: scheme.surface,
      extensions: <ThemeExtension<dynamic>>[appColors],
    );
  }
}
