import 'package:flutter/material.dart';

/// Brand-fixed, theme-INVARIANT scrim colors drawn over live media (the QR camera
/// feed) — black at fixed opacities, NOT part of the `ColorScheme` (design-system.md
/// §9.9). Hand-written (these are not design-token-JSON colors, so they don't belong
/// in the generated `nox_*.dart`) and kept in the theme layer so the presentation
/// widgets carry no raw `Color` literals.
abstract final class NoxScrims {
  /// Viewfinder dimming mask around the reticle (~55% black).
  static const Color qrMask = Color(0x8C000000);

  /// "Enter manually" pill fill over the camera feed (~35% black).
  static const Color qrPill = Color(0x59000000);

  /// Instruction text shadow for legibility over the feed (~80% black).
  static const Color qrTextShadow = Color(0xCC000000);
}
