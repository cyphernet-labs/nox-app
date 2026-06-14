import 'package:flutter/material.dart';

/// Semantic, mode-dependent colors layered on the M3 `ColorScheme` via
/// `ThemeExtension`. ONLY roles that are opacity-modified or absent from the
/// stock `ColorScheme` live here; everything else reads `ColorScheme` directly
/// (design-system.md §9 channel rule). Values are DERIVED from the scheme (which
/// derives from nox-handoff tokens) via [AppColors.fromScheme] — no manual hex.
/// Source: design-system.md §2.6 (timestamp 70%), §9.3/§9.11.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.timestamp,
    required this.dividerSubtle,
    required this.surfaceMuted,
    required this.disabledContainer,
    required this.disabledContent,
    required this.dragHandle,
  });

  /// Derive the semantic extras from a base [ColorScheme] (token-driven).
  factory AppColors.fromScheme(ColorScheme s) => AppColors(
    timestamp: s.onSurfaceVariant.withValues(alpha: 0.70), // §2.6/§9.2 message + list timestamps
    dividerSubtle: s.outlineVariant, // §9.3 hairline divider between list rows
    surfaceMuted: s.surfaceContainerHighest, // muted grouped surface (settings sections)
    disabledContainer: s.onSurface.withValues(alpha: 0.12), // M3 disabled container tint
    disabledContent: s.onSurface.withValues(alpha: 0.38), // M3 disabled content tint
    dragHandle: s.onSurfaceVariant.withValues(alpha: 0.40), // §9.11 bottom-sheet drag handle
  );

  final Color timestamp;
  final Color dividerSubtle;
  final Color surfaceMuted;
  final Color disabledContainer;
  final Color disabledContent;
  final Color dragHandle;

  @override
  AppColors copyWith({
    Color? timestamp,
    Color? dividerSubtle,
    Color? surfaceMuted,
    Color? disabledContainer,
    Color? disabledContent,
    Color? dragHandle,
  }) {
    return AppColors(
      timestamp: timestamp ?? this.timestamp,
      dividerSubtle: dividerSubtle ?? this.dividerSubtle,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      disabledContainer: disabledContainer ?? this.disabledContainer,
      disabledContent: disabledContent ?? this.disabledContent,
      dragHandle: dragHandle ?? this.dragHandle,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      timestamp: Color.lerp(timestamp, other.timestamp, t)!,
      dividerSubtle: Color.lerp(dividerSubtle, other.dividerSubtle, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      disabledContainer: Color.lerp(disabledContainer, other.disabledContainer, t)!,
      disabledContent: Color.lerp(disabledContent, other.disabledContent, t)!,
      dragHandle: Color.lerp(dragHandle, other.dragHandle, t)!,
    );
  }
}

extension AppColorsExtension on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
