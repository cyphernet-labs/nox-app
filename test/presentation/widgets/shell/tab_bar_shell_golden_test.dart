@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/presentation/widgets/shell/app_navigation_rail_widget.dart';
import 'package:nox_app/presentation/widgets/shell/tab_bar_shell_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/fonts.dart';
import '../../../utils/golden.dart';
import '../../../utils/pump_app.dart';

/// Screen-level golden for the 4.1 assembled tab-bar shell (DoD tail / E2): the live
/// shell with its default Chats tab — page-mobile (360, bottom bar + docked FAB) +
/// page-desktop (1280x800, window titlebar + rail w/ account avatar + list-detail).
/// The shell hosts REACTIVE tabs (watchChats + mock seed delays), so — like the chat
/// thread golden — this bespoke harness mirrors `golden.dart` but settles with
/// BOUNDED pumps instead of pumpAndSettle.
Future<void> _settleShell(WidgetTester tester) async {
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  setUpAll(loadNoxFonts);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase(); // fresh store → deterministic seed
    // A signed-in session so the desktop rail account avatar renders a stable label.
    await getIt<SessionRepository>().saveIdentifier(identifier: 'sess-golden', onboardingComplete: true, label: 'Nova');
  });

  tearDown(() async {
    await getIt.reset();
  });

  group('tab_bar_shell golden', () {
    for (final entry in const <(ThemeMode, String)>[(ThemeMode.light, 'light'), (ThemeMode.dark, 'dark')]) {
      final mode = entry.$1;
      final suffix = entry.$2;

      testWidgets('mobile matches the $suffix theme', (tester) async {
        AppClock.freeze(kGoldenClock);
        addTearDown(AppClock.reset);
        tester.view.devicePixelRatio = 3.0;
        tester.view.physicalSize = Constants.designSize * 3.0;
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
        });

        await pumpApp(tester, const TabBarShell(), themeMode: mode, settle: false);
        await _settleShell(tester);

        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/tab_bar_shell_$suffix.png'));
      });

      testWidgets('desktop matches the $suffix theme', (tester) async {
        AppClock.freeze(kGoldenClock);
        addTearDown(AppClock.reset);
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = kDesktopGoldenSize * 2.0;
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
        });

        await pumpApp(tester, const TabBarShell(), themeMode: mode, settle: false);
        await _settleShell(tester);

        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/tab_bar_shell_desktop_$suffix.png'));
      });

      // Settings tab active on desktop — locks the rail selected state, the Settings
      // detail within the shell, and the R3 titlebar subtitle following the tab
      // ('· Settings', not the hardcoded '· Chats' the strip previously always showed).
      testWidgets('desktop Settings tab matches the $suffix theme', (tester) async {
        AppClock.freeze(kGoldenClock);
        addTearDown(AppClock.reset);
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = kDesktopGoldenSize * 2.0;
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
        });

        await pumpApp(tester, const TabBarShell(), themeMode: mode, settle: false);
        await _settleShell(tester);
        // Activate Settings via the rail destination (disambiguated from the settings body text).
        await tester.tap(find.descendant(of: find.byType(AppNavigationRailWidget), matching: find.text('Settings')));
        await _settleShell(tester);

        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/tab_bar_shell_settings_desktop_$suffix.png'));
      });
    }
  });
}
