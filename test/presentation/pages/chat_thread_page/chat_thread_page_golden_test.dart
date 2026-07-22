@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/presentation/pages/chat_thread_page/chat_thread_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/fonts.dart';
import '../../../utils/golden.dart';
import '../../../utils/pump_app.dart';

/// Screen-level golden for the 5.2 chat thread (DoD tail / E1): page-mobile (360) +
/// page-desktop (1280x800, `_wide` thread pane). The thread is a REACTIVE page
/// (watchMessages + mock seed delays), so the standard `goldenTest` harness can't be
/// used — pumpAndSettle would hang and `settle: false` would snapshot the spinner.
/// This bespoke harness mirrors `golden.dart` (frozen clock, real fonts, pinned
/// surface) but settles with BOUNDED pumps, like the reactive widget tests.
ChatModel _chat() =>
    ChatModel(id: 'chat_0', name: 'Design crit', lastMessagePreview: '', lastMessageAt: DateTime.fromMillisecondsSinceEpoch(0));

Future<void> _settleThread(WidgetTester tester) async {
  // Bounded pumps (not pumpAndSettle): the reactive watchMessages subscription + the
  // mock seed delays keep timers in flight, which pumpAndSettle would wait on forever.
  // ~2.1s drains the two-page seed (150ms each) + the debounced refresh, leaving the
  // loaded thread on a stable frame.
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
  });

  tearDown(() async {
    await getIt.reset();
  });

  group('chat_thread_page golden', () {
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

        await pumpApp(tester, ChatThreadPage(chat: _chat()), themeMode: mode, settle: false);
        await _settleThread(tester);

        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/chat_thread_page_$suffix.png'));
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

        await pumpApp(tester, ChatThreadPage(chat: _chat()), themeMode: mode, settle: false);
        await _settleThread(tester);

        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/chat_thread_page_desktop_$suffix.png'));
      });
    }
  });
}
