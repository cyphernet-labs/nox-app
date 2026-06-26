import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/constants.dart';

import 'fonts.dart';
import 'pump_app.dart';

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
/// Desktop/wide branches (`>= Constants.railBreakpoint`) are verified by widget
/// tests, not by goldens.
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
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/${name}_$suffix.png'));
      });
    }
  });
}
