import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/theme/nox_color_scheme.dart';

// Polish / FR-024, SC-010: WCAG AA contrast for load-bearing role/background
// pairs of the NOX ColorScheme (both modes). Body text >= 4.5:1; large text /
// icons / non-text >= 3:1. Guards against token edits regressing accessibility.
double _lin(double c) => c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) => 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void _checkScheme(String name, ColorScheme s) {
  group('$name contrast', () {
    test('on-color vs its container — body text >= 4.5:1', () {
      expect(_contrast(s.onSurface, s.surface), greaterThanOrEqualTo(4.5), reason: 'onSurface/surface');
      expect(_contrast(s.onPrimary, s.primary), greaterThanOrEqualTo(4.5), reason: 'onPrimary/primary');
      expect(_contrast(s.onPrimaryContainer, s.primaryContainer), greaterThanOrEqualTo(4.5), reason: 'onPrimaryContainer/primaryContainer');
      expect(
        _contrast(s.onSecondaryContainer, s.secondaryContainer),
        greaterThanOrEqualTo(4.5),
        reason: 'onSecondaryContainer/secondaryContainer',
      );
      expect(_contrast(s.onErrorContainer, s.errorContainer), greaterThanOrEqualTo(4.5), reason: 'onErrorContainer/errorContainer');
      expect(
        _contrast(s.onInverseSurface, s.inverseSurface),
        greaterThanOrEqualTo(4.5),
        reason: 'onInverseSurface/inverseSurface (snackbar)',
      );
    });
    test('secondary text & non-text — >= 3:1', () {
      expect(_contrast(s.onSurfaceVariant, s.surface), greaterThanOrEqualTo(3.0), reason: 'onSurfaceVariant/surface (secondary)');
      expect(_contrast(s.outline, s.surface), greaterThanOrEqualTo(3.0), reason: 'outline/surface (non-text)');
    });
  });
}

void main() {
  _checkScheme('light', noxLightScheme);
  _checkScheme('dark', noxDarkScheme);
}
