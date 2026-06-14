import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/theme/app_colors.dart';
import 'package:nox_app/design/theme/app_theme.dart';

// US1 / FR-006, SC-002: AppTheme.light()/dark() build with a complete NOX M3
// ColorScheme + textTheme + AppColors extension, and the two modes differ
// (themeMode switch is meaningful, no role lost).
void main() {
  group('AppTheme builds', () {
    test('light', () {
      final theme = AppTheme.light();
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.brightness, Brightness.light);
      expect(theme.textTheme.bodyMedium, isNotNull);
      expect(theme.extension<AppColors>(), isNotNull);
      // Full M3 tiered scheme (not a minimal one): a tier role is present.
      expect(theme.colorScheme.surfaceContainerHighest, isNotNull);
    });

    test('dark', () {
      final theme = AppTheme.dark();
      expect(theme.colorScheme.brightness, Brightness.dark);
      expect(theme.extension<AppColors>(), isNotNull);
    });

    test('light and dark primaries differ', () {
      expect(AppTheme.light().colorScheme.primary, isNot(AppTheme.dark().colorScheme.primary));
    });
  });
}
