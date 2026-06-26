import 'package:nox_app/design/app_spacing_tokens.dart';

/// Semantic dimension roles. Every role references an [AppSpacingTokens] step
/// BY NAME — no loose numbers. Grouped access: `AppDimensionTokens.space.md`,
/// `.radius.lg`, `.icon.base`, `.size.appBarH`, etc. Values are responsive (the
/// scale multiplies by the ScreenUtil factor), so members are getters — access
/// ONLY inside `build` under `ScreenUtilInit`.
abstract final class AppDimensionTokens {
  const AppDimensionTokens._();

  static const AppSpaceTokens space = AppSpaceTokens._();
  static const AppRadiusTokens radius = AppRadiusTokens._();
  static const AppBorderTokens border = AppBorderTokens._();
  static const AppIconTokens icon = AppIconTokens._();
  static const AppSizeTokens size = AppSizeTokens._();
}

/// Padding / gap roles (space.*).
final class AppSpaceTokens {
  const AppSpaceTokens._();

  double get zero => AppSpacingTokens.s0;
  double get hair => AppSpacingTokens.s2;
  double get micro => AppSpacingTokens.s4;
  double get xs => AppSpacingTokens.s6;
  double get sm => AppSpacingTokens.s8;
  double get md => AppSpacingTokens.s12;
  double get lg => AppSpacingTokens.s16; // screen horizontal padding
  double get xl => AppSpacingTokens.s20;
  double get xxl => AppSpacingTokens.s24;
  double get xxxl => AppSpacingTokens.s32;
  double get huge => AppSpacingTokens.s40;
  double get jumbo => AppSpacingTokens.s56;
}

/// Corner-radius roles (radius.*), mirroring the NoxRadius ramp. `pill` is fully-rounded.
final class AppRadiusTokens {
  const AppRadiusTokens._();

  double get none => AppSpacingTokens.s0;
  double get xs => AppSpacingTokens.s4; // TextField, file-chip
  double get sm => AppSpacingTokens.s8; // small chips, segments
  double get md => AppSpacingTokens.s12; // Card (identity)
  double get lg => AppSpacingTokens.s16; // message bubble base
  double get xl => AppSpacingTokens.s28; // bottom sheet, AlertDialog
  double get pill => AppSpacingTokens.s999;
}

/// Stroke / border-width roles (border.*).
final class AppBorderTokens {
  const AppBorderTokens._();

  double get hairline => AppSpacingTokens.s1;
  double get regular => AppSpacingTokens.s1_5;
  double get thick => AppSpacingTokens.s2;
}

/// Icon render-size roles (icon.*). `base` (22) is the default for most UI.
final class AppIconTokens {
  const AppIconTokens._();

  double get micro => AppSpacingTokens.s12;
  double get xs => AppSpacingTokens.s14;
  double get sm => AppSpacingTokens.s16;
  double get md => AppSpacingTokens.s18;
  double get lg => AppSpacingTokens.s20;
  double get base => AppSpacingTokens.s22;
  double get xl => AppSpacingTokens.s24;
  double get xxl => AppSpacingTokens.s28;
  double get glyph => AppSpacingTokens.s32;
}

/// Fixed component & layout sizes (size.*). `hitTarget` (48) is the minimum
/// interactive tap target.
final class AppSizeTokens {
  const AppSizeTokens._();

  double get screenPad => AppSpacingTokens.s16;
  double get hitTarget => AppSpacingTokens.s48;
  double get appBarH => AppSpacingTokens.s64; // M3 small top app bar
  double get bottomNavH => AppSpacingTokens.s72;
  double get fieldH => AppSpacingTokens.s56;
  double get buttonH => AppSpacingTokens.s40; // visible pill; tap target padded to 48
  double get searchBarH => AppSpacingTokens.s56;
  double get idFieldMinH => AppSpacingTokens.s120; // Login multiline paste-target
  double get avatarSm => AppSpacingTokens.s40;
  double get avatarMd => AppSpacingTokens.s48;
  double get avatarLg => AppSpacingTokens.s56;
  double get illustrationIcon => AppSpacingTokens.s80; // error / empty-state hero icon
  double get fileGlyphBox => AppSpacingTokens.s128;
  double get fileGlyphIcon => AppSpacingTokens.s72;
  double get splashLogo => AppSpacingTokens.s168;
}
