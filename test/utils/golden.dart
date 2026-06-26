import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/general/constants.dart';

import 'fonts.dart';
import 'pump_app.dart';

/// `pumpAndSettle` does NOT await async PNG decoding, so the brand logo asset
/// (AppOnboardCardWidget head / launcher) can snapshot BLANK non-deterministically.
/// Precache it on SETTLED screens so logo-bearing goldens capture it reliably
/// (animated `settle: false` screens never render the logo, so skip them — pumping
/// them again would only shift the animation a frame). Mirrors splash_page_golden_test.dart.
Future<void> _settleWithBrandLogo(WidgetTester tester, bool settle) async {
  if (!settle) return;
  await tester.runAsync(() => precacheImage(Assets.png.logo.provider(), tester.element(find.byType(MaterialApp))));
  await tester.pumpAndSettle();
}

/// Runs a curated golden for [name] in BOTH light and dark, on the fixed design
/// surface, against `goldens/<name>_<mode>.png` (relative to the calling test
/// file). [settle] = false for animated content (spinners). Local-only harness —
/// see .claude/commands/golden-test.md (`@Tags(['golden'])`, excluded from CI).
///
/// NOTE: the surface is pinned to `Constants.designSize` (the 360 mobile width
/// that drives ScreenUtil) by sizing the `FlutterView` directly — `setSurfaceSize`
/// resizes the render canvas but does NOT reach the MediaQuery ScreenUtil reads, so
/// it would leave ScreenUtil at the default 800x600 and scale every token ~1.5x
/// inside a 360 canvas. With the view pinned, ScreenUtil resolves at scale 1.0 and
/// goldens are the true MOBILE design. dpr 3 keeps the PNG crisp (1080x2337).
/// Desktop/wide branches (`>= Constants.railBreakpoint`) get their own baselines via
/// [goldenTestDesktop].
void goldenTest(String name, Widget Function() build, {bool settle = true}) {
  group('$name golden', () {
    setUpAll(loadNoxFonts);
    for (final entry in const <(ThemeMode, String)>[(ThemeMode.light, 'light'), (ThemeMode.dark, 'dark')]) {
      final mode = entry.$1;
      final suffix = entry.$2;
      testWidgets('matches the $suffix theme', (tester) async {
        tester.view.devicePixelRatio = 3.0;
        tester.view.physicalSize = Constants.designSize * 3.0;
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
        });
        await pumpApp(tester, build(), themeMode: mode, settle: settle);
        await _settleWithBrandLogo(tester, settle);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/${name}_$suffix.png'));
      });
    }
  });
}

/// Canonical DESKTOP golden window (logical px) — a representative laptop window
/// comfortably past `Constants.railBreakpoint` (840), so pages select their
/// `_wide` / master-detail / window-titlebar branch. Platform-agnostic: the five
/// desktop targets (macOS/Windows/Linux) share one Flutter wide layout, so a single
/// wide-surface baseline IS "the desktop golden".
const Size kDesktopGoldenSize = Size(1280, 800);

/// Desktop counterpart of [goldenTest]: renders [build] on the wide
/// [kDesktopGoldenSize] window in BOTH light and dark, against
/// `goldens/<name>_desktop_<mode>.png`. Same harness as the mobile path, only the
/// pinned surface differs — so a screen can own BOTH a mobile and a desktop
/// baseline. ScreenUtil resolves spacing/fonts through the production clamps at this
/// surface (spacing → 1.2 ceiling, fonts → 1.0 ceiling), so the baseline reflects
/// the real desktop rendering, not an up-scaled phone. dpr 2 mirrors a Retina
/// display and keeps glyphs crisp. [settle] = false for animated content.
void goldenTestDesktop(String name, Widget Function() build, {bool settle = true, Size size = kDesktopGoldenSize}) {
  group('$name desktop golden', () {
    setUpAll(loadNoxFonts);
    for (final entry in const <(ThemeMode, String)>[(ThemeMode.light, 'light'), (ThemeMode.dark, 'dark')]) {
      final mode = entry.$1;
      final suffix = entry.$2;
      testWidgets('matches the $suffix theme', (tester) async {
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = size * 2.0;
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
        });
        await pumpApp(tester, build(), themeMode: mode, settle: settle);
        await _settleWithBrandLogo(tester, settle);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/${name}_desktop_$suffix.png'));
      });
    }
  });
}
