import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nox_app/design/theme/nox_text_theme.dart';

/// Responsive type-scale tokens — the full NOX M3 scale (9 roles) as color-injecting factories.
///
/// One factory per role in `noxTextTheme` (`nox_text_theme.dart`), reproducing its
/// `fontSize` / `fontWeight` / `letterSpacing`. Sizes use `.sp`, but `.sp` is globally
/// CLAMPED by [fontSizeResolver] (registered on every `ScreenUtilInit`) so type never
/// balloons on a wide desktop window and converges with the fixed-px `noxTextTheme`
/// there. Callers pass the resolved color from `context.appColors` / `ColorScheme`.
///
/// These factories deliberately set **no** `height`: NOX's `Theme.textTheme`
/// (`noxTextTheme`, fixed design px — see `AppTheme`) carries the design line-height for
/// full-fidelity text, and pinning an explicit line-height here regresses the
/// `textScaler: 2.0` no-overflow guarantee (FR-016 a11y) in fixed columns. For text that
/// must carry the design line-height, use `Theme.of(context).textTheme.<role>`.
/// They also set no `fontFamily` (inherited from the theme — `Roboto`).
///
/// Call only inside `build` under `ScreenUtilInit` (`.sp` is valid only after it runs).
abstract final class AppTextStyleTokens {
  const AppTextStyleTokens._();

  /// Clamp band for the global font scale ([fontSizeResolver]). The ceiling is 1.0 —
  /// type NEVER grows on a wide window — so the responsive `.sp` tokens CONVERGE with
  /// the fixed-px `noxTextTheme` on desktop instead of rendering the same role at two
  /// sizes. The 0.9 floor keeps sub-360 / split-screen text legible. Deliberately
  /// tighter than the spacing band (AppSpacingTokens clamps 0.85–1.2): padding may
  /// breathe on a wide canvas, but type stays anchored to its reading-distance-correct
  /// size (M3: the type scale is fixed; form factors adapt via layout/columns, not glyph
  /// size).
  static const double fontScaleMin = 0.90;
  static const double fontScaleMax = 1.00;

  /// Global `ScreenUtilInit.fontSizeResolver` — register on EVERY `ScreenUtilInit` (app
  /// + test harness) so every `.sp` (the tokens below and any stray widget usage) is
  /// clamped consistently. flutter_screenutil's DEFAULT resolver is width-only with NO
  /// upper bound: at design width 360 a 1440-wide desktop window yields a 4.0 factor, so
  /// `16.sp` would render at 64dp — the desktop "balloon". This uses the SAME averaged
  /// width/height metric AppSpacingTokens uses for spacing, bounded to
  /// [fontScaleMin]–[fontScaleMax]. At the 360 design surface the factors are 1.0 → scale
  /// 1.0 (goldens unchanged).
  static double fontSizeResolver(num fontSize, ScreenUtil instance) {
    final scale = ((instance.scaleWidth + instance.scaleHeight) / 2).clamp(fontScaleMin, fontScaleMax);
    return (fontSize * scale).toDouble();
  }

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
