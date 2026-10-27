@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/domain/model/connection/connection_status.dart';
import 'package:nox_app/domain/service/connection_status_service.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/presentation/pages/chat_thread_page/chat_thread_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/fixed_connection_status.dart';
import '../../../utils/fonts.dart';
import '../../../utils/golden.dart';
import '../../../utils/pump_app.dart';

/// 5.2 with the connection corner (phase 040): the narrow app bar - before
/// the invite seam - through Tor and coming up through Tor. Same bounded-pump
/// harness as chat_thread_page_golden_test.dart, for the same reason: the
/// thread is reactive and pumpAndSettle would never return.
ChatModel _chat() =>
    ChatModel(id: 'chat_0', name: 'Design crit', lastMessagePreview: '', lastMessageAt: DateTime.fromMillisecondsSinceEpoch(0));

Future<void> _settleThread(WidgetTester tester) async {
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
      testWidgets('mobile ${state.$1} matches the ${entry.$2} theme', (tester) async {
        AppClock.freeze(kGoldenClock);
        addTearDown(AppClock.reset);
        tester.view.devicePixelRatio = 3.0;
        tester.view.physicalSize = Constants.designSize * 3.0;
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
        });
        status.value = state.$2;

        await pumpApp(tester, ChatThreadPage(chat: _chat()), themeMode: entry.$1, settle: false);
        await _settleThread(tester);

        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/chat_thread_page_${state.$1}_${entry.$2}.png'));
      });
    }
  }
}
