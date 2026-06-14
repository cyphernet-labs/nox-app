import 'package:flutter/material.dart';

/// Brand-fixed component tokens that are NOT theme-dependent (independent of
/// light/dark) and do NOT map to a `ColorScheme` role — design-system.md §9.9
/// (QR scanner / camera overlay) and §9.10 (QR bottom sheet). The QR surface /
/// ink themselves live in `NoxBrand` (qrSurface / qrInk). Raw Color literals are
/// allowed here (this is a token file). See also `AppColors` (theme-dependent
/// extras) and `NoxBrand` (brand palette).
abstract final class NoxComponentTokens {
  const NoxComponentTokens._();

  /// §9.9 — dim mask painted over the live camera feed outside the viewfinder.
  /// Black at 55% opacity (0x8C ≈ 0.549).
  static const Color scannerMask = Color(0x8C000000);

  /// §9.9 — viewfinder reticle / framing corners over the live feed.
  static const Color scannerReticle = Color(0xFFFAFAFA);

  /// §9.9 — instruction text над живым видео ("Point your camera at a QR code").
  static const Color scannerInstruction = Color(0xFFFAFAFA);
}
