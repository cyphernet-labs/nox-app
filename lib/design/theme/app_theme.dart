import 'package:flutter/material.dart';
import 'package:nox_app/design/theme/app_colors.dart';
import 'package:nox_app/design/theme/nox_color_scheme.dart';
import 'package:nox_app/design/theme/nox_component_themes.dart';
import 'package:nox_app/design/theme/nox_text_theme.dart';

/// NOX Material 3 theme. The `ColorScheme` and `TextTheme` come from the
/// token-generated design-system handoff (`lib/design/theme/nox_*.dart`,
/// regenerated from `docs/design/system/nox-handoff/tokens` — never hand-edited),
/// so the palette is the hand-tuned NOX teal scheme, not a raw `fromSeed`.
/// Semantic, mode-dependent extras ride along via the AppColors ThemeExtension.
class AppTheme {
  const AppTheme._();

  // Themes are static per ColorScheme; build once and cache so MaterialApp
  // rebuilds (e.g. every AppRootBloc emission) don't reconstruct all sub-themes.
  static ThemeData? _light;
  static ThemeData? _dark;

  static ThemeData light() => _light ??= _build(noxLightScheme, const LightAppColors());

  static ThemeData dark() => _dark ??= _build(noxDarkScheme, const DarkAppColors());

  static ThemeData _build(ColorScheme scheme, AppColors appColors) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: noxTextTheme,
      scaffoldBackgroundColor: scheme.surface,
      // Stock-widget M3 component themes (lib/design/theme/nox_component_themes.dart).
      appBarTheme: noxAppBarTheme(scheme),
      filledButtonTheme: noxFilledButtonTheme(scheme),
      textButtonTheme: noxTextButtonTheme(scheme),
      iconButtonTheme: noxIconButtonTheme(scheme),
      inputDecorationTheme: noxInputDecorationTheme(scheme),
      segmentedButtonTheme: noxSegmentedButtonTheme(scheme),
      switchTheme: noxSwitchTheme(scheme),
      radioTheme: noxRadioTheme(scheme),
      listTileTheme: noxListTileTheme(scheme),
      progressIndicatorTheme: noxProgressIndicatorTheme(scheme),
      dialogTheme: noxDialogTheme(scheme),
      bottomSheetTheme: noxBottomSheetTheme(scheme),
      cardTheme: noxCardTheme(scheme),
      snackBarTheme: noxSnackBarTheme(scheme),
      extensions: <ThemeExtension<dynamic>>[appColors],
    );
  }
}
