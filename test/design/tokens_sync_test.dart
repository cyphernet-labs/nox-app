import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/design/theme/nox_text_theme.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';

/// US4 / FR-008, FR-010 / SC-004 — representative token values stay consistent with the
/// authoritative nox-handoff. Guards against drift without a brittle byte-for-byte diff.
void main() {
  test('spacing / radius / elevation / motion', () {
    expect(NoxSpacing.s4, 16);
    expect(NoxRadius.xl, 28);
    expect(NoxElevation.level2, 3);
    expect(NoxDuration.push, const Duration(milliseconds: 300));
  });

  test('typography representative values', () {
    expect(noxTextTheme.bodyMedium!.fontSize, 14);
    expect(noxTextTheme.titleMedium!.fontWeight, FontWeight.w500);
  });

  test('brand-fixed colors (theming exceptions) and avatar palette', () {
    expect(NoxBrand.canvasDark, const Color(0xFF0C2424)); // splash background
    expect(NoxBrand.qrSurface, const Color(0xFFFFFFFF)); // QR surface
    expect(NoxBrand.qrInk, const Color(0xFF0C0C0C)); // QR ink
    expect(noxAvatarPalette.length, 8);
  });
}
