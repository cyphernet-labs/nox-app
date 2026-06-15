import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Responsive type-scale tokens — the full NOX M3 scale as color-injecting factories.
///
/// One factory per role used by `noxTextTheme` (`nox_text_theme.dart`), with the same
/// `fontSize`/`fontWeight`. Sizes use `.sp` (responsive); callers pass the resolved color
/// from `context.appColors` / `ColorScheme`. These factories set **no** `height` (line
/// height comes from `noxTextTheme`, so it scales once with `fontSize`, not quadratically)
/// and **no** `fontFamily` (the family — `Roboto` — is inherited from the theme).
///
/// Call only inside `build` under `ScreenUtilInit` (`.sp` is valid only after it runs).
abstract final class AppTextStyleTokens {
  const AppTextStyleTokens._();

  /// 36 / w400 — display small.
  static TextStyle displaySmall({required Color color}) => TextStyle(fontSize: 36.sp, fontWeight: FontWeight.w400, color: color);

  /// 24 / w400 — headline small.
  static TextStyle headlineSmall({required Color color}) => TextStyle(fontSize: 24.sp, fontWeight: FontWeight.w400, color: color);

  /// 22 / w400 — title large.
  static TextStyle titleLarge({required Color color}) => TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w400, color: color);

  /// 16 / w500 — title medium.
  static TextStyle titleMedium({required Color color}) => TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w500, color: color);

  /// 16 / w400 — body large.
  static TextStyle bodyLarge({required Color color}) => TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w400, color: color);

  /// 14 / w400 — body medium.
  static TextStyle bodyMedium({required Color color}) => TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w400, color: color);

  /// 14 / w500 — label large.
  static TextStyle labelLarge({required Color color}) => TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500, color: color);

  /// 12 / w500 — label medium.
  static TextStyle labelMedium({required Color color}) => TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500, color: color);
}
