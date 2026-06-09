// GENERATED — NOX ThemeData (light + dark) wiring tokens into M3 components.
// Component bindings follow design-system.md §9. Tune to taste; this is a
// faithful starting point, not the final production theme.
import 'package:flutter/material.dart';
import 'nox_color_scheme.dart';
import 'nox_text_theme.dart';
import 'nox_tokens.dart';

ThemeData _base(ColorScheme scheme) {
  final cs = scheme;
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    textTheme: noxTextTheme,
    scaffoldBackgroundColor: cs.surface,

    appBarTheme: AppBarTheme(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      elevation: 0,
      scrolledUnderElevation: NoxElevation.level2,
      centerTitle: false,
      titleTextStyle: noxTextTheme.titleLarge?.copyWith(color: cs.onSurface),
    ),

    // FilledButton (primary) — stadium, Label Large
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

    // TextField (outlined) — shape/xs, outline → primary on focus
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

    // Cards (identity card) — shape/m, level 1
    cardTheme: CardThemeData(
      color: cs.surfaceContainerLow,
      elevation: NoxElevation.level1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NoxRadius.m)),
      margin: EdgeInsets.zero,
    ),

    // Docked FAB "+" — circle, primaryContainer, level 3
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: cs.primaryContainer,
      foregroundColor: cs.onPrimaryContainer,
      elevation: NoxElevation.level3,
      shape: const CircleBorder(),
    ),
    bottomAppBarTheme: BottomAppBarTheme(
      color: cs.surfaceContainer,
      elevation: NoxElevation.level2,
    ),

    // Bottom sheet + dialog — shape/xl, level 5
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cs.surface,
      elevation: NoxElevation.level5,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(NoxRadius.xl)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cs.surfaceContainerHigh,
      elevation: NoxElevation.level5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NoxRadius.xl)),
      titleTextStyle: noxTextTheme.headlineSmall?.copyWith(color: cs.onSurface),
      contentTextStyle: noxTextTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
    ),

    // Snackbar — inverseSurface; error variant set per-call to errorContainer
    snackBarTheme: SnackBarThemeData(
      backgroundColor: cs.inverseSurface,
      contentTextStyle: noxTextTheme.bodyMedium?.copyWith(color: cs.onInverseSurface),
      actionTextColor: cs.inversePrimary,
      behavior: SnackBarBehavior.floating,
    ),

    // SegmentedButton — selected secondaryContainer
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(NoxRadius.s)),
        ),
      ),
    ),

    dividerTheme: DividerThemeData(color: cs.outlineVariant, thickness: 1, space: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: cs.primary,
      linearTrackColor: cs.surfaceContainerHighest,
    ),

    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}

final ThemeData noxLightTheme = _base(noxLightScheme);
final ThemeData noxDarkTheme  = _base(noxDarkScheme);

// Usage:
//   MaterialApp(
//     theme: noxLightTheme,
//     darkTheme: noxDarkTheme,
//     themeMode: ThemeMode.system, // Settings 7.3: System / Light / Dark
//   );
