import 'package:flutter/material.dart';
import 'package:nox_app/design/theme/nox_text_theme.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';

/// Per-component M3 sub-themes wiring NOX tokens into stock Material widgets, so
/// `FilledButton`/`TextField`/`SegmentedButton`/`AlertDialog`/etc. look like NOX
/// without custom classes. Bindings follow nox-handoff-2/spec/components.md and
/// the reference `flutter/nox_theme.dart`. Assembled by [AppTheme].

AppBarTheme noxAppBarTheme(ColorScheme cs) => AppBarTheme(
  backgroundColor: cs.surface,
  foregroundColor: cs.onSurface,
  elevation: NoxElevation.level0,
  scrolledUnderElevation: NoxElevation.level2,
  centerTitle: false,
  titleTextStyle: noxTextTheme.titleLarge?.copyWith(color: cs.onSurface),
);

FilledButtonThemeData noxFilledButtonTheme(ColorScheme cs) => FilledButtonThemeData(
  style: FilledButton.styleFrom(
    backgroundColor: cs.primary,
    foregroundColor: cs.onPrimary,
    shape: const StadiumBorder(),
    textStyle: noxTextTheme.labelLarge,
    minimumSize: const Size(0, NoxSpacing.minTapTarget),
  ),
);

TextButtonThemeData noxTextButtonTheme(ColorScheme cs) => TextButtonThemeData(
  style: TextButton.styleFrom(
    foregroundColor: cs.primary,
    shape: const StadiumBorder(),
    textStyle: noxTextTheme.labelLarge,
    minimumSize: const Size(0, NoxSpacing.minTapTarget),
  ),
);

IconButtonThemeData noxIconButtonTheme(ColorScheme cs) => IconButtonThemeData(
  style: IconButton.styleFrom(
    foregroundColor: cs.onSurfaceVariant,
    minimumSize: const Size(NoxSpacing.minTapTarget, NoxSpacing.minTapTarget),
  ),
);

InputDecorationTheme noxInputDecorationTheme(ColorScheme cs) {
  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(NoxRadius.xs),
    borderSide: BorderSide(color: color, width: width),
  );
  return InputDecorationTheme(
    filled: false,
    border: border(cs.outline),
    enabledBorder: border(cs.outline),
    focusedBorder: border(cs.primary, 2),
    errorBorder: border(cs.error),
    helperStyle: noxTextTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
    counterStyle: noxTextTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
  );
}

SegmentedButtonThemeData noxSegmentedButtonTheme(ColorScheme cs) => const SegmentedButtonThemeData(
  // Design: the segmented control is a full stadium (pill), like the M3 default and the
  // other NOX buttons — not the 8px rounded box we used to force.
  style: ButtonStyle(shape: WidgetStatePropertyAll(StadiumBorder())),
);

SwitchThemeData noxSwitchTheme(ColorScheme cs) => SwitchThemeData(
  thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? cs.onPrimary : cs.outline),
  trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? cs.primary : cs.surfaceContainerHighest),
  trackOutlineColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? Colors.transparent : cs.outline),
  // NOTE: the design shows a check glyph on the ON thumb, but `thumbIcon` only accepts a
  // Material `Icon` (icon font) — and NOX is SVG-only (MaterialIcons is not loaded in the
  // golden harness, so it renders as tofu). Left off deliberately; the teal track + thumb
  // position already read ON/OFF unambiguously. (audit [24], intentionally skipped)
);

RadioThemeData noxRadioTheme(ColorScheme cs) => RadioThemeData(
  fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? cs.primary : cs.onSurfaceVariant),
);

ListTileThemeData noxListTileTheme(ColorScheme cs) => ListTileThemeData(iconColor: cs.onSurfaceVariant, textColor: cs.onSurface);

ProgressIndicatorThemeData noxProgressIndicatorTheme(ColorScheme cs) =>
    ProgressIndicatorThemeData(color: cs.primary, linearTrackColor: cs.surfaceContainerHighest);

DialogThemeData noxDialogTheme(ColorScheme cs) => DialogThemeData(
  backgroundColor: cs.surfaceContainerHigh,
  elevation: NoxElevation.level5,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NoxRadius.xl)),
  titleTextStyle: noxTextTheme.headlineSmall?.copyWith(color: cs.onSurface),
  contentTextStyle: noxTextTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
);

BottomSheetThemeData noxBottomSheetTheme(ColorScheme cs) => BottomSheetThemeData(
  backgroundColor: cs.surface,
  elevation: NoxElevation.level5,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(NoxRadius.xl))),
);

CardThemeData noxCardTheme(ColorScheme cs) => CardThemeData(
  color: cs.surfaceContainerLow,
  elevation: NoxElevation.level1,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NoxRadius.m)),
  margin: EdgeInsets.zero,
);

SnackBarThemeData noxSnackBarTheme(ColorScheme cs) => SnackBarThemeData(
  backgroundColor: cs.inverseSurface,
  contentTextStyle: noxTextTheme.bodyMedium?.copyWith(color: cs.onInverseSurface),
  actionTextColor: cs.inversePrimary,
  behavior: SnackBarBehavior.floating,
);

// 5.1 Chats list — permanent M3 SearchBar under the AppBar.
SearchBarThemeData noxSearchBarTheme(ColorScheme cs) => SearchBarThemeData(
  backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerHigh),
  elevation: const WidgetStatePropertyAll(NoxElevation.level2),
  shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(NoxRadius.full))),
  hintStyle: WidgetStatePropertyAll(noxTextTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
  textStyle: WidgetStatePropertyAll(noxTextTheme.bodyLarge?.copyWith(color: cs.onSurface)),
);

// 5.1 Chats list — offline / inline-error banner (showAppBanner).
MaterialBannerThemeData noxMaterialBannerTheme(ColorScheme cs) => MaterialBannerThemeData(
  backgroundColor: cs.surfaceContainer,
  elevation: NoxElevation.level3,
  contentTextStyle: noxTextTheme.bodyMedium?.copyWith(color: cs.onSurface),
);

// 5.1 Chats list — unread badge uses the `primary` role (NOT the stock error-red).
BadgeThemeData noxBadgeTheme(ColorScheme cs) =>
    BadgeThemeData(backgroundColor: cs.primary, textColor: cs.onPrimary, textStyle: noxTextTheme.labelSmall);

// 4.1 Tab-bar shell — desktop NavigationRail (selected = primary).
NavigationRailThemeData noxNavigationRailTheme(ColorScheme cs) => NavigationRailThemeData(
  backgroundColor: cs.surface,
  selectedIconTheme: IconThemeData(color: cs.primary),
  unselectedIconTheme: IconThemeData(color: cs.onSurfaceVariant),
  selectedLabelTextStyle: noxTextTheme.labelMedium?.copyWith(color: cs.primary),
  unselectedLabelTextStyle: noxTextTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
  indicatorColor: cs.secondaryContainer,
);
