@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/connection/connection_status.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/service/connection_status_service.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:nox_app/presentation/widgets/shell/tab_bar_shell_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/fixed_connection_status.dart';
import '../../../utils/fonts.dart';
import '../../../utils/golden.dart';
import '../../../utils/pump_app.dart';

/// The wide shell with the connection corner at the right edge of the window
/// titlebar (phase 040): through Tor, and coming up through Tor. Bounded pumps
/// like tab_bar_shell_golden_test.dart - the tabs are reactive.
Future<void> _settleShell(WidgetTester tester) async {
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  setUpAll(loadNoxFonts);

  late FixedConnectionStatusService status;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase();
    await getIt<SessionRepository>().saveIdentifier(identifier: 'sess-golden', onboardingComplete: true, label: 'Nova');
    status = FixedConnectionStatusService();
    getIt.allowReassignment = true;
    getIt.registerSingleton<ConnectionStatusService>(status);
  });

  tearDown(() async {
    await getIt.reset();
  });

  for (final state in const <(String, ConnectionStatus)>[
    ('tor', FixedConnectionStatusService.tor),
    ('connecting_tor', FixedConnectionStatusService.connectingTor),
  ]) {
    for (final entry in const <(ThemeMode, String)>[(ThemeMode.light, 'light'), (ThemeMode.dark, 'dark')]) {
      testWidgets('desktop ${state.$1} matches the ${entry.$2} theme', (tester) async {
        AppClock.freeze(kGoldenClock);
        addTearDown(AppClock.reset);
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = kDesktopGoldenSize * 2.0;
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
        });
        status.value = state.$2;

        await pumpApp(tester, const TabBarShell(), themeMode: entry.$1, settle: false);
        await _settleShell(tester);

        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/tab_bar_shell_${state.$1}_desktop_${entry.$2}.png'));
      });
    }
  }
}
