@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/presentation/pages/splash_page/splash_page.dart';

import '../../../utils/fonts.dart';
import '../../../utils/pump_app.dart';

/// Bespoke golden (not the shared `goldenTest` helper) because the brand logo is a
/// PNG asset: its decode is async and NOT awaited by `pumpAndSettle`, so it must be
/// precached or the snapshot is non-deterministic (logo present in one theme, blank
/// in the other). Brand-fixed dark canvas → light and dark goldens are identical by
/// design (one of the two sanctioned theming exceptions).
void main() {
  group('splash_page golden', () {
    setUpAll(loadNoxFonts);
    for (final entry in const <(ThemeMode, String)>[(ThemeMode.light, 'light'), (ThemeMode.dark, 'dark')]) {
      final mode = entry.$1;
      final suffix = entry.$2;
      testWidgets('matches the $suffix theme', (tester) async {
        await tester.binding.setSurfaceSize(Constants.designSize);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pumpApp(tester, const SplashPage(), themeMode: mode, settle: false);
        await tester.runAsync(() async {
          await precacheImage(Assets.png.logo.provider(), tester.element(find.byType(SplashPage)));
        });
        await tester.pumpAndSettle(); // finish the one-shot reveal -> final static frame
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/splash_page_$suffix.png'));
      });
    }
  });
}
