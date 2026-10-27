import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/settings_root_page/settings_root_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
  });

  tearDown(() async {
    await getIt.reset();
  });

  // No desktop target here sets a minimum window size, so a short window is not
  // a hypothetical: macOS opens its default window at 800x600. As one
  // unscrollable Column with a Spacer the pane clipped its last rows behind an
  // overflow stripe from 598px down - measured at 1280 wide, overflow = 598.4 -
  // height - and there was no way to reach them, `Log out` included.
  testWidgets('the desktop menu pane survives a short window, and keeps Log out reachable', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final height in <double>[800, 700, 620, 599, 598, 560, 480, 400]) {
      await tester.binding.setSurfaceSize(Size(1280, height));
      await pumpApp(tester, const SettingsRootPage(inShell: true, forceWide: true), settle: false);
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull, reason: 'the pane overflowed at ${height}px');
      // Pinned to the foot rather than scrolled away with the destinations.
      expect(find.text(l10nEn.logoutRow), findsOneWidget, reason: 'Log out is gone at ${height}px');
    }
  });
}
