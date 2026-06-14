import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/theme/nox_color_scheme.dart';

// US1 / FR-001, FR-017, SC-003: guard against drift between the generated
// schemes and the authoritative nox-handoff color tokens. Spot-checks
// load-bearing roles (a hand-edit to nox_color_scheme.dart would fail here).
void main() {
  test('light scheme matches authoritative tokens', () {
    expect(noxLightScheme.brightness, Brightness.light);
    expect(noxLightScheme.primary, const Color(0xFF006A6A));
    expect(noxLightScheme.surface, const Color(0xFFF4FBFA));
    expect(noxLightScheme.onSurface, const Color(0xFF161D1D));
    expect(noxLightScheme.outline, const Color(0xFF6F7979));
    expect(noxLightScheme.outlineVariant, const Color(0xFFBEC9C8));
    expect(noxLightScheme.error, const Color(0xFFBA1A1A));
  });

  test('dark scheme matches authoritative tokens (incl. outlineVariant)', () {
    expect(noxDarkScheme.brightness, Brightness.dark);
    // Authoritative token == code == 0xFF4E5B58 (NOT the stale design-system.md
    // §2.3 prose #3F4948 — see research.md §G / FR-017).
    expect(noxDarkScheme.outlineVariant, const Color(0xFF4E5B58));
  });
}
