import 'package:flutter/material.dart';

/// Semantic, mode-dependent colors layered on top of the M3 ColorScheme via
/// ThemeExtension. Raw Color literals are allowed ONLY in this theme file.
/// Skeleton uses a minimal set; the full token-driven palette (from
/// docs/design/system/nox-handoff/) lands in US4.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.surfaceMuted,
    required this.dividerSubtle,
  });

  final Color surfaceMuted;
  final Color dividerSubtle;

  @override
  AppColors copyWith({Color? surfaceMuted, Color? dividerSubtle}) {
    return AppColors(
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      dividerSubtle: dividerSubtle ?? this.dividerSubtle,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      dividerSubtle: Color.lerp(dividerSubtle, other.dividerSubtle, t)!,
    );
  }
}

class LightAppColors extends AppColors {
  const LightAppColors()
      : super(
          surfaceMuted: const Color(0xFFF2F2F2),
          dividerSubtle: const Color(0xFFBDBDBD),
        );
}

class DarkAppColors extends AppColors {
  const DarkAppColors()
      : super(
          surfaceMuted: const Color(0xFF2D2D2D),
          dividerSubtle: const Color(0xFF000000),
        );
}

extension AppColorsExtension on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
