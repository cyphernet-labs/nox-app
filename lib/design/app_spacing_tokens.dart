import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Responsive numeric scale. Each step is the design-px value scaled by
/// flutter_screenutil, so it adapts to device size. The semantic layer
/// (`AppDimensionTokens`) references these by name — UI code should prefer the
/// semantic roles and use raw `sN` only for one-off gaps.
///
/// Getters (not `static final`) so the scale is recomputed on every access and
/// stays correct after a resize/rotation. Access ONLY inside `build` under
/// `ScreenUtilInit` (`.w`/`.h` are valid only after it runs).
abstract final class AppSpacingTokens {
  const AppSpacingTokens._();

  // Mean of width/height scale factors, so spacing stays balanced on extreme
  // aspect ratios (desktop/landscape), not just width-driven (blueprint 06 §4).
  static double get _scale => (1.w + 1.h) / 2;

  static double get s0 => 0;
  static double get s1 => 1 * _scale;
  static double get s1_5 => 1.5 * _scale;
  static double get s2 => 2 * _scale;
  static double get s3 => 3 * _scale;
  static double get s4 => 4 * _scale;
  static double get s6 => 6 * _scale;
  static double get s8 => 8 * _scale;
  static double get s10 => 10 * _scale;
  static double get s12 => 12 * _scale;
  static double get s14 => 14 * _scale;
  static double get s16 => 16 * _scale;
  static double get s18 => 18 * _scale;
  static double get s20 => 20 * _scale;
  static double get s22 => 22 * _scale;
  static double get s24 => 24 * _scale;
  static double get s26 => 26 * _scale;
  static double get s28 => 28 * _scale;
  static double get s30 => 30 * _scale;
  static double get s32 => 32 * _scale;
  static double get s36 => 36 * _scale;
  static double get s40 => 40 * _scale;
  static double get s44 => 44 * _scale;
  static double get s48 => 48 * _scale;
  static double get s52 => 52 * _scale;
  static double get s56 => 56 * _scale;
  static double get s64 => 64 * _scale;
  static double get s72 => 72 * _scale;
  static double get s80 => 80 * _scale;
  static double get s88 => 88 * _scale;
  static double get s96 => 96 * _scale;
  static double get s120 => 120 * _scale;
  static double get s128 => 128 * _scale;
  static double get s132 => 132 * _scale;
  static double get s160 => 160 * _scale;
  static double get s168 => 168 * _scale;
  static double get s220 => 220 * _scale;
  static double get s280 => 280 * _scale;
  static double get s300 => 300 * _scale;

  /// Fully-rounded radius marker (radius.pill). A large unscaled constant used
  /// with `BorderRadius.circular` / `StadiumBorder`.
  static double get s999 => 999;
}
