import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nox_app/design/theme/nox_text_theme.dart';

/// Responsive type-scale tokens — the full NOX M3 scale (9 roles) as color-injecting factories.
///
/// One factory per role in `noxTextTheme` (`nox_text_theme.dart`), reproducing its
/// `fontSize` / `fontWeight` / `letterSpacing`. Sizes use `.sp` (responsive); callers pass
/// the resolved color from `context.appColors` / `ColorScheme`.
///
/// These factories deliberately set **no** `height` — it would scale quadratically with `.sp`
/// (`.sp` already scales `fontSize`, and `height` is a multiplier of it); line height is supplied
/// by the ambient `DefaultTextStyle` / the matching `Theme.textTheme` role. They also set no
/// `fontFamily` (inherited from the theme — `Roboto`). For full-fidelity text that must carry the
/// design line-height, use `Theme.of(context).textTheme.<role>` directly.
///
/// Call only inside `build` under `ScreenUtilInit` (`.sp` is valid only after it runs).
abstract final class AppTextStyleTokens {
  const AppTextStyleTokens._();

  /// 36 / w400 — display small.
  static TextStyle displaySmall({required Color color}) =>
      TextStyle(fontSize: 36.sp, fontWeight: FontWeight.w400, letterSpacing: 0, color: color);

  /// 24 / w400 — headline small.
  static TextStyle headlineSmall({required Color color}) =>
      TextStyle(fontSize: 24.sp, fontWeight: FontWeight.w400, letterSpacing: 0, color: color);

  /// 22 / w400 — title large.
  static TextStyle titleLarge({required Color color}) =>
      TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w400, letterSpacing: 0, color: color);

  /// 16 / w500 — title medium.
  static TextStyle titleMedium({required Color color}) =>
      TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w500, letterSpacing: 0.15, color: color);

  /// 16 / w400 — body large.
  static TextStyle bodyLarge({required Color color}) =>
      TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w400, letterSpacing: 0.5, color: color);

  /// 14 / w400 — body medium.
  static TextStyle bodyMedium({required Color color}) =>
      TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w400, letterSpacing: 0.25, color: color);

  /// 14 / w500 — label large.
  static TextStyle labelLarge({required Color color}) =>
      TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500, letterSpacing: 0.1, color: color);

  /// 12 / w500 — label medium.
  static TextStyle labelMedium({required Color color}) =>
      TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500, letterSpacing: 0.5, color: color);

  /// 11 / w500 — label small.
  static TextStyle labelSmall({required Color color}) =>
      TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w500, letterSpacing: 0.5, color: color);

  /// 16 / w400 / Roboto Mono — the long identifier string (Login 2.1, Settings ID).
  /// Monospaced so the key-like characters align; family from [noxMonoFamily].
  static TextStyle monoBody({required Color color}) =>
      TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w400, letterSpacing: 0, fontFamily: noxMonoFamily, color: color);
}
