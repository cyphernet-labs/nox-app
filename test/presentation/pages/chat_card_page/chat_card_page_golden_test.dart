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
import 'package:nox_app/presentation/pages/chat_card_page/bloc/chat_card_bloc.dart';
import 'package:nox_app/presentation/pages/chat_card_page/chat_card_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/fonts.dart';
import '../../../utils/golden.dart';
import '../../../utils/pump_app.dart';

/// Goldens for the Chat card (5.4): page-mobile (pushed full-screen — header + Files
/// list) and page-desktop (the `_wide` right side-sheet). The files view now DERIVES
/// from the chat's persisted attachments (feature 017 / E3) — `chat_0`'s seeded thread
/// carries one file (`design-spec.pdf`), so the list is non-empty. Because the card is
/// now REACTIVE (R5, watchMessages), the standard `goldenTest` harness (pumpAndSettle)
/// can't be used — this bespoke harness mirrors `golden.dart` but settles with BOUNDED
/// pumps (like `chat_thread_page_golden_test.dart`).
ChatModel _chat() => ChatModel(id: 'chat_0', name: 'Design crit', lastMessagePreview: '', lastMessageAt: DateTime(2024, 1, 1));

Future<void> _settleCard(WidgetTester tester) async {
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  setUpAll(loadNoxFonts);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase();
  });

  tearDown(() async {
    await getIt.reset();
  });

  group('chat_card_page golden', () {
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

        await pumpApp(tester, ChatCardPage(chat: _chat()), themeMode: mode, settle: false);
        await _settleCard(tester);

        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/chat_card_page_$suffix.png'));
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

        await pumpApp(tester, ChatCardPage(chat: _chat()), themeMode: mode, settle: false);
        await _settleCard(tester);

        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/chat_card_page_desktop_$suffix.png'));
      });

      // Debug scenarios + the grid view (P10). offline = a NOTICE strip over the files
      // list; empty = the empty-files illustration; fatal = full-screen error; grid = the
      // files GridView (normal scenario, forced via initialViewMode). Mobile + desktop.
      for (final variant in _cardVariants) {
        testWidgets('mobile ${variant.name} matches the $suffix theme', (tester) async {
          AppClock.freeze(kGoldenClock);
          addTearDown(AppClock.reset);
          tester.view.devicePixelRatio = 3.0;
          tester.view.physicalSize = Constants.designSize * 3.0;
          addTearDown(() {
            tester.view.resetDevicePixelRatio();
            tester.view.resetPhysicalSize();
          });

          await pumpApp(
            tester,
            ChatCardPage(chat: _chat(), initialScenario: variant.scenario, initialViewMode: variant.viewMode),
            themeMode: mode,
            settle: false,
          );
          await _settleCard(tester);

          await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/chat_card_page_${variant.name}_$suffix.png'));
        });

        testWidgets('desktop ${variant.name} matches the $suffix theme', (tester) async {
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
            ChatCardPage(chat: _chat(), initialScenario: variant.scenario, initialViewMode: variant.viewMode),
            themeMode: mode,
            settle: false,
          );
          await _settleCard(tester);

          await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/chat_card_page_${variant.name}_desktop_$suffix.png'));
        });
      }
    }
  });
}

/// The card debug variants locked by P10. `scenario`/`viewMode` are set independently
/// (a scenario re-initializes and would reset viewMode), so `grid` carries no scenario.
typedef _CardVariant = ({String name, ChatCardScenario? scenario, FilesViewMode? viewMode});

const List<_CardVariant> _cardVariants = [
  (name: 'offline', scenario: ChatCardScenario.offline, viewMode: null),
  (name: 'empty', scenario: ChatCardScenario.empty, viewMode: null),
  (name: 'fatal', scenario: ChatCardScenario.fatal, viewMode: null),
  (name: 'grid', scenario: null, viewMode: FilesViewMode.grid),
];
