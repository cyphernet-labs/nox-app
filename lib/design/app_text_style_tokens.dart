import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Typography scale. Color-injecting factory methods (NOT const TextStyle) —
/// callers pass the resolved color from `context.appColors` / ColorScheme.
abstract final class AppTextStyleTokens {
  const AppTextStyleTokens._();

  static TextStyle body({required Color color}) => TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w400, color: color);

  static TextStyle title({required Color color}) => TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600, color: color);

  static TextStyle caption({required Color color}) => TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w400, color: color);
}
