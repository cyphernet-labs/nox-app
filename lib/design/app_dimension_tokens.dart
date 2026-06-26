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
  static const AppLayoutTokens layout = AppLayoutTokens._();
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
  double get heavy => AppSpacingTokens.s3; // splash hairline / QR overlay strokes
}

/// Icon render-size roles (icon.*). `base` (22) is the default for most UI;
/// `hero` (48) is the error/empty-state and file-view glyph icon.
final class AppIconTokens {
  const AppIconTokens._();

  double get micro => AppSpacingTokens.s12;
  double get xs => AppSpacingTokens.s14; // message status tick
  double get sm => AppSpacingTokens.s16;
  double get md => AppSpacingTokens.s18; // in-button spinner
  double get lg => AppSpacingTokens.s20; // identity-card / strip actions
  double get base => AppSpacingTokens.s22; // default list-leading icon
  double get xl => AppSpacingTokens.s24;
  double get fab => AppSpacingTokens.s26; // central create FAB glyph
  double get xxl => AppSpacingTokens.s28; // file-chip / grid-glyph icon
  double get glyph => AppSpacingTokens.s32;
  double get hero => AppSpacingTokens.s48; // error/empty + file-view glyph icon
  double get heroWide => AppSpacingTokens.s96; // error illustration icon on wide layouts
}

/// Fixed component & element sizes (size.*). `hitTarget` (48) is the minimum
/// interactive tap target. Each role maps to a real drawn element in the UI.
final class AppSizeTokens {
  const AppSizeTokens._();

  double get screenPad => AppSpacingTokens.s16;
  double get hitTarget => AppSpacingTokens.s48;

  // Avatars (circle diameters).
  double get avatarXs => AppSpacingTokens.s36; // thread header
  double get avatarSm => AppSpacingTokens.s40; // chat list row
  double get avatarMd => AppSpacingTokens.s48;
  double get avatarLg => AppSpacingTokens.s56; // chat card / identity card

  // File-type glyph boxes (the rounded square behind the type icon).
  double get fileGlyphSm => AppSpacingTokens.s40; // chat-card file list
  double get fileGlyphMd => AppSpacingTokens.s56; // chat-card file grid
  double get fileGlyphLg => AppSpacingTokens.s96; // file-view header

  // Component chrome heights.
  double get bottomBarH => AppSpacingTokens.s64; // docked bottom bar
  double get searchBarH => AppSpacingTokens.s56;
  double get windowTitlebarH => AppSpacingTokens.s40; // desktop custom titlebar
  double get chatRowMinH => AppSpacingTokens.s72; // chat list row min height
  double get fabNotchGap => AppSpacingTokens.s72; // bottom-bar central FAB notch

  // Hero / brand elements.
  double get splashLogo => AppSpacingTokens.s168; // splash logo (mobile)
  double get splashLogoWide => AppSpacingTokens.s220; // splash logo (desktop)
  double get onboardLogoH => AppSpacingTokens.s64; // onboarding card logo
  double get qrSurface => AppSpacingTokens.s160; // identity-card QR (brand-fixed light)
  double get qrScanWindow => AppSpacingTokens.s300; // QR scanner viewfinder square
  double get emptyArt => AppSpacingTokens.s132; // empty-state illustration box
}

/// UNSCALED content-width bounds (layout.*). Unlike every other group these do NOT
/// multiply by the device scale: they cap line length / panel width for
/// readability, so growing them on wide screens would defeat their purpose. Plain
/// design-px constants, named so widgets carry no magic `maxWidth` numbers.
final class AppLayoutTokens {
  const AppLayoutTokens._();

  double get dialogMaxW => 460; // create-chat modal
  double get sheetMaxW => 320; // list-detail / side sheet
  double get contentMaxW => 520; // file view / centered form column
  double get settingsMaxW => 680; // settings content column
  double get galleryMaxW => 640; // dev screens gallery
  double get fileChipMinW => 200;
  double get fileChipMaxW => 260;
  double get messageMaxW => 260; // empty-state message column
  double get chatsListPaneW => 360; // chats master-detail list pane
  double get settingsListPaneW => 340; // settings master-detail list pane
  double get sideSheetW => 380; // desktop right side-sheet (chat card)
}
