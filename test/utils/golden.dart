import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/constants.dart';

import 'fonts.dart';
import 'pump_app.dart';

/// Runs a curated golden for [name] in BOTH light and dark, on the fixed design
/// surface, against `goldens/<name>_<mode>.png` (relative to the calling test
/// file). [settle] = false for animated content (spinners). Local-only harness —
/// see .claude/commands/golden-test.md (`@Tags(['golden'])`, excluded from CI).
void goldenTest(String name, Widget Function() build, {bool settle = true}) {
  group('$name golden', () {
    setUpAll(loadNoxFonts);
    for (final entry in const <(ThemeMode, String)>[(ThemeMode.light, 'light'), (ThemeMode.dark, 'dark')]) {
      final mode = entry.$1;
      final suffix = entry.$2;
      testWidgets('matches the $suffix theme', (tester) async {
        await tester.binding.setSurfaceSize(Constants.designSize);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pumpApp(tester, build(), themeMode: mode, settle: settle);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/${name}_$suffix.png'));
      });
    }
  });
}
