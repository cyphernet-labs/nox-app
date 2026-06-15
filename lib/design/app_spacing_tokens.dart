import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Responsive spacing scale. Each step is the design-px value scaled by
/// flutter_screenutil (`.w`), so it adapts to device width.
abstract final class AppSpacingTokens {
  const AppSpacingTokens._();

  // Mean of width/height scale factors, so spacing stays balanced on extreme
  // aspect ratios (desktop/landscape), not just width-driven (blueprint 06 §4).
  static double get _scale => (1.w + 1.h) / 2;

  static double get s2 => 2 * _scale;
  static double get s4 => 4 * _scale;
  static double get s6 => 6 * _scale;
  static double get s8 => 8 * _scale;
  static double get s10 => 10 * _scale;
  static double get s12 => 12 * _scale;
  static double get s14 => 14 * _scale;
  static double get s16 => 16 * _scale;
  static double get s20 => 20 * _scale;
  static double get s24 => 24 * _scale;
  static double get s28 => 28 * _scale;
  static double get s32 => 32 * _scale;
}
