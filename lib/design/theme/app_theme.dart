import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:nox_app/design/theme/app_colors.dart';
import 'package:nox_app/design/theme/nox_color_scheme.dart';
import 'package:nox_app/design/theme/nox_text_theme.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';

/// NOX Material 3 theme. The `ColorScheme` and `TextTheme` come from the
/// token-generated design-system handoff (`lib/design/theme/nox_*.dart`,
/// regenerated from `docs/design/system/nox-handoff/tokens` — never hand-edited),
/// so the palette is the hand-tuned NOX teal scheme, not a raw `fromSeed`.
/// Semantic mode-dependent extras ride along via the `AppColors` ThemeExtension,
/// and component sub-themes bind the tokens (`NoxRadius`/`NoxElevation`) to M3
/// components per design-system.md §9 — so widgets inherit the NOX look with no
/// local styling. Component sub-themes (this file) is the design-layer config;
/// the widgets themselves are out of scope for the design-system feature.
class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(noxLightScheme);

  static ThemeData dark() => _build(noxDarkScheme);

  static ThemeData _build(ColorScheme cs) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      textTheme: noxTextTheme,
      scaffoldBackgroundColor: cs.surface,
      extensions: <ThemeExtension<dynamic>>[AppColors.fromScheme(cs)],

      // AppBar — flat, surface, Title Large (§9.11).
      appBarTheme: AppBarTheme(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: NoxElevation.level0,
        scrolledUnderElevation: NoxElevation.level2,
        centerTitle: false,
        titleTextStyle: noxTextTheme.titleLarge?.copyWith(color: cs.onSurface),
      ),

      // FilledButton (primary) / TextButton — stadium, Label Large (§9.5).
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          shape: const StadiumBorder(),
          textStyle: noxTextTheme.labelLarge,
          minimumSize: const Size(0, NoxSpacing.minTapTarget),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: cs.primary,
          shape: const StadiumBorder(),
          textStyle: noxTextTheme.labelLarge,
          minimumSize: const Size(0, NoxSpacing.minTapTarget),
        ),
      ),

      // TextField (outlined) — shape/xs, outline -> primary on focus (§9.5).
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NoxRadius.xs),
          borderSide: BorderSide(color: cs.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NoxRadius.xs),
          borderSide: BorderSide(color: cs.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NoxRadius.xs),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NoxRadius.xs),
          borderSide: BorderSide(color: cs.error),
        ),
        helperStyle: noxTextTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        counterStyle: noxTextTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
      ),

      // Card (identity card) — shape/m, level 1 (§9.4).
      cardTheme: CardThemeData(
        color: cs.surfaceContainerLow,
        elevation: NoxElevation.level1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NoxRadius.m)),
        margin: EdgeInsets.zero,
      ),

      // Docked FAB "+" — circle, primaryContainer, level 3 (§9.1).
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        elevation: NoxElevation.level3,
        shape: const CircleBorder(),
      ),
      bottomAppBarTheme: BottomAppBarThemeData(color: cs.surfaceContainer, elevation: NoxElevation.level2),

      // Adaptive shell nav (§9.1) — bottom bar (mobile) / rail (desktop).
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cs.surfaceContainer,
        indicatorColor: cs.secondaryContainer,
        elevation: NoxElevation.level2,
        labelTextStyle: WidgetStatePropertyAll(noxTextTheme.labelMedium),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: cs.surface,
        indicatorColor: cs.secondaryContainer,
        selectedLabelTextStyle: noxTextTheme.labelMedium?.copyWith(color: cs.onSurface),
        unselectedLabelTextStyle: noxTextTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
      ),

      // Bottom sheet + dialog — shape/xl, level 5 (§9.10/§9.11).
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.surface,
        elevation: NoxElevation.level5,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(NoxRadius.xl))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cs.surfaceContainerHigh,
        elevation: NoxElevation.level5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NoxRadius.xl)),
        titleTextStyle: noxTextTheme.headlineSmall?.copyWith(color: cs.onSurface),
        contentTextStyle: noxTextTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
      ),

      // SnackBar — inverseSurface; error variant set per-call to errorContainer (§9.11).
      snackBarTheme: SnackBarThemeData(
        backgroundColor: cs.inverseSurface,
        contentTextStyle: noxTextTheme.bodyMedium?.copyWith(color: cs.onInverseSurface),
        actionTextColor: cs.inversePrimary,
        behavior: SnackBarBehavior.floating,
      ),

      // SearchBar — stadium, level 2 (§9.5).
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(NoxElevation.level2),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(NoxRadius.full))),
      ),

      // SegmentedButton — shape/s; selected uses secondaryContainer (§9.5).
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(NoxRadius.s)))),
      ),

      dividerTheme: DividerThemeData(color: cs.outlineVariant, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: cs.primary, linearTrackColor: cs.surfaceContainerHighest),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {TargetPlatform.android: ZoomPageTransitionsBuilder(), TargetPlatform.iOS: CupertinoPageTransitionsBuilder()},
      ),
    );
  }
}
