import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';

/// Canonical **responsive layout-spacing** channel. Each step is the raw dp value
/// from [NoxSpacing] (the token-generated source) scaled by flutter_screenutil, so
/// spacing values are single-sourced — the 06 §4.1 duplication is resolved:
/// `NoxSpacing` = raw dp source + fixed-dp tokens (`minTapTarget` / `screenPadding`);
/// `AppSpacingTokens` = responsive layout consumption (use THIS for EdgeInsets/gaps).
abstract final class AppSpacingTokens {
  const AppSpacingTokens._();

  // Mean of width/height scale factors, so spacing stays balanced on extreme
  // aspect ratios (desktop/landscape), not just width-driven (blueprint 06 §4).
  static double get _scale => (1.w + 1.h) / 2;

  static double get s4 => NoxSpacing.s1 * _scale;
  static double get s8 => NoxSpacing.s2 * _scale;
  static double get s12 => NoxSpacing.s3 * _scale;
  static double get s16 => NoxSpacing.s4 * _scale;
  static double get s24 => NoxSpacing.s6 * _scale;
  static double get s28 => 28 * _scale; // one-off (AppBar bottom); not a 4dp-grid token
  static double get s32 => NoxSpacing.s8 * _scale;
}
