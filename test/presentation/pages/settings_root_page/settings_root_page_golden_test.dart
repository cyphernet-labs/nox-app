@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';
import 'package:nox_app/presentation/pages/settings_root_page/settings_root_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/fake_session_repository.dart';
import '../../../utils/fonts.dart';
import '../../../utils/golden.dart';
import '../../../utils/pump_app.dart';

void main() {
  group('settings root', () {
    // The identity card / Show QR loads the id from the session spine on init.
    setUpAll(registerFakeSession);
    tearDownAll(getIt.reset);

    // Mobile layout: identity card + flat settings rows + Log out.
    goldenTest('settings_root_page', () => BlocProvider<AppRootBloc>(create: (_) => AppRootBloc(), child: const SettingsRootPage()));
    // Desktop `_wide` branch: the list-detail (master list + detail pane).
    goldenTestDesktop('settings_root_page', () => BlocProvider<AppRootBloc>(create: (_) => AppRootBloc(), child: const SettingsRootPage()));
  });

  // Connection selected in the desktop menu (phase 045): the section fills the
  // detail pane, its item drawn filled. The pane reads the real stores of the
  // test environment - the paired address, nothing from a server yet.
  group('settings root, Connection selected', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await configureDependencies(Environment.test);
      registerFakeSession();
      await loadNoxFonts();
    });
    tearDownAll(getIt.reset);

    for (final (mode, suffix) in const [(ThemeMode.light, 'light'), (ThemeMode.dark, 'dark')]) {
      testWidgets('desktop matches the $suffix theme', (tester) async {
        AppClock.freeze(kGoldenClock);
        addTearDown(AppClock.reset);
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = kDesktopGoldenSize * 2.0;
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
        });
        await pumpApp(
          tester,
          BlocProvider<AppRootBloc>(create: (_) => AppRootBloc(), child: const SettingsRootPage()),
          themeMode: mode,
        );

        await tester.tap(find.widgetWithText(ListTile, AppLocalizationsEn().settingsConnectionTitle));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/settings_root_page_connection_desktop_$suffix.png'));
      });
    }
  });
}
