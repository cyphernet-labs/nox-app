import 'package:flutter/material.dart';
import 'package:nox_app/design/theme/app_colors.dart';
import 'package:nox_app/design/theme/nox_color_scheme.dart';
import 'package:nox_app/design/theme/nox_component_themes.dart';
import 'package:nox_app/design/theme/nox_text_theme.dart';

/// NOX Material 3 theme. The `ColorScheme` and base `TextTheme` come from the
/// token-generated design-system handoff (`lib/design/theme/nox_*.dart`,
/// regenerated from `docs/design/system/nox-handoff/tokens` — never hand-edited),
/// so the palette is the hand-tuned NOX teal scheme, not a raw `fromSeed`.
/// Semantic, mode-dependent extras ride along via the AppColors ThemeExtension.
///
/// Built FRESH each call (NOT cached): per-component sub-themes pull responsive
/// sizes/radii from `AppDimensionTokens` and the opt-in `AppTextStyleTokens`
/// (`.sp`/`.w`), which are only valid under `ScreenUtilInit` and must recompute
/// per surface. The global `Theme.textTheme` deliberately stays the canonical
/// design type-scale (`noxTextTheme`, fixed design px) — responsive text is opt-in
/// via `AppTextStyleTokens`; scaling the whole scale destabilizes every
/// stock-widget layout (and the FR-016 textScaler stress) for no design gain.
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
      searchBarTheme: noxSearchBarTheme(scheme),
      bannerTheme: noxMaterialBannerTheme(scheme),
      badgeTheme: noxBadgeTheme(scheme),
      navigationRailTheme: noxNavigationRailTheme(scheme),
      extensions: <ThemeExtension<dynamic>>[appColors],
    );
  }
}
