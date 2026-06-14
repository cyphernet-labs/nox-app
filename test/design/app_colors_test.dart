import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/theme/app_colors.dart';
import 'package:nox_app/design/theme/app_theme.dart';
import 'package:nox_app/design/theme/nox_color_scheme.dart';

// US2 / FR-007: AppColors is the full token-driven semantic-extras set (not the
// 2-field skeleton), derived from the ColorScheme (tokens), and rides on the
// ThemeData for both modes.
void main() {
  test('AppColors.fromScheme derives the full semantic role set', () {
    final c = AppColors.fromScheme(noxLightScheme);
    expect(c.timestamp.a, closeTo(0.70, 0.01)); // onSurfaceVariant @ 70%
    expect(c.dividerSubtle, noxLightScheme.outlineVariant);
    expect(c.surfaceMuted, noxLightScheme.surfaceContainerHighest);
    expect(c.disabledContainer.a, closeTo(0.12, 0.01));
    expect(c.disabledContent.a, closeTo(0.38, 0.01));
    expect(c.dragHandle.a, closeTo(0.40, 0.01));
  });

  test('theme exposes AppColors for light and dark', () {
    expect(AppTheme.light().extension<AppColors>(), isNotNull);
    expect(AppTheme.dark().extension<AppColors>(), isNotNull);
  });

  test('light and dark AppColors differ (mode-dependent)', () {
    final light = AppTheme.light().extension<AppColors>()!;
    final dark = AppTheme.dark().extension<AppColors>()!;
    expect(light.surfaceMuted, isNot(dark.surfaceMuted));
  });
}
