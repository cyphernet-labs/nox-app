import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Responsive spacing scale. Each step is the design-px value scaled by
/// flutter_screenutil (`.w`), so it adapts to device width.
abstract final class AppSpacingTokens {
  const AppSpacingTokens._();

  static double get _scale => 1.w;

  static double get s4 => 4 * _scale;
  static double get s8 => 8 * _scale;
  static double get s12 => 12 * _scale;
  static double get s16 => 16 * _scale;
  static double get s24 => 24 * _scale;
  static double get s28 => 28 * _scale;
  static double get s32 => 32 * _scale;
}
