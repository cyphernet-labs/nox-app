import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/create_chat_page/create_chat_page.dart';
import 'package:nox_app/presentation/pages/chats_list_page/chats_list_page.dart';
import 'package:nox_app/presentation/pages/settings_root_page/settings_root_page.dart';
import 'package:nox_app/presentation/widgets/shell/app_bottom_bar_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_create_fab_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_list_detail_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_navigation_rail_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_window_titlebar_widget.dart';
import 'package:nox_app/presentation/widgets/shell/tab_bar_shell_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  // The shell hosts the real Chats list, whose bloc resolves ChatRepository from DI.
  setUpAll(() async {
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async {
    await getIt.reset();
  });

  group('TabBarShell', () {
    AppBottomBarWidget bottomBar(WidgetTester tester) => tester.widget<AppBottomBarWidget>(find.byType(AppBottomBarWidget));

    testWidgets('narrow window shows the bottom bar + docked FAB, not the rail', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const TabBarShell());
      await tester.pump(const Duration(milliseconds: 300)); // the chats tab fetches its page
      await tester.pumpAndSettle();

      expect(find.byType(AppBottomBarWidget), findsOneWidget);
      expect(find.byType(AppCreateFabWidget), findsOneWidget);
      expect(find.byType(AppNavigationRailWidget), findsNothing);
    });

    testWidgets('wide window shows the navigation rail, not the bottom bar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const TabBarShell());
      await tester.pump(const Duration(milliseconds: 300)); // the chats tab fetches its page
      await tester.pumpAndSettle();

      expect(find.byType(AppNavigationRailWidget), findsOneWidget);
      expect(find.byType(AppBottomBarWidget), findsNothing);
    });

    testWidgets('in the rail band (window just over 840) the body follows the shell into desktop list-detail', (tester) async {
      // Window >= 840 (rail shown) but the rail-narrowed body width < 840: without
      // forceWide the body would wrongly render its mobile branch.
      await tester.binding.setSurfaceSize(const Size(880, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const TabBarShell());
      await tester.pump(const Duration(milliseconds: 300)); // the chats tab fetches its page
      await tester.pumpAndSettle();

      expect(find.byType(AppNavigationRailWidget), findsOneWidget);
      // Both tab bodies use the desktop list-detail container (not the mobile chrome).
      expect(find.byType(AppListDetailWidget), findsWidgets);
      expect(find.byType(AppBottomBarWidget), findsNothing);
    });

    testWidgets('keeps both tab bodies in the tree (state preserved) and switches the active tab', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const TabBarShell());
      await tester.pump(const Duration(milliseconds: 300)); // the chats tab fetches its page
      await tester.pumpAndSettle();

      // Both bodies are always mounted (IndexedStack-like preservation, FR-021).
      expect(find.byType(ChatsListPage), findsOneWidget);
      expect(find.byType(SettingsRootPage), findsOneWidget);
      expect(bottomBar(tester).active, AppTab.chats);

      await tester.tap(find.descendant(of: find.byType(AppBottomBarWidget), matching: find.text(l10nEn.settings)));
      await tester.pumpAndSettle();

      expect(bottomBar(tester).active, AppTab.settings);
      // Bodies still both mounted after the switch.
      expect(find.byType(ChatsListPage), findsOneWidget);
      expect(find.byType(SettingsRootPage), findsOneWidget);
    });

    testWidgets('central + opens the real Create chat (6.1)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const TabBarShell());
      await tester.pump(const Duration(milliseconds: 300)); // the chats tab fetches its page
      await tester.pumpAndSettle();

      await tester.tap(find.byType(AppCreateFabWidget));
      await tester.pumpAndSettle();

      expect(find.byType(CreateChatPage), findsOneWidget);
    });

    testWidgets('rail + opens Create chat as a real modal Dialog on desktop (N5)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900)); // wide → rail
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const TabBarShell());
      await tester.pump(const Duration(milliseconds: 300)); // the chats tab fetches its page
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(l10nEn.tooltipCreateChat)); // the rail's + → _onCreate(desktop: true)
      await tester.pumpAndSettle();

      // A real showDialog modal (not a pushed route with a simulated scrim).
      expect(find.byType(CreateChatPage), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('system back on a non-Chats tab returns to Chats instead of popping the shell', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const TabBarShell());
      await tester.pump(const Duration(milliseconds: 300)); // the chats tab fetches its page
      await tester.pumpAndSettle();

      // Go to Settings.
      await tester.tap(find.descendant(of: find.byType(AppBottomBarWidget), matching: find.text(l10nEn.settings)));
      await tester.pumpAndSettle();
      expect(bottomBar(tester).active, AppTab.settings);

      // PopScope blocks the pop and the handler routes back to Chats.
      final popScope = tester.widget<PopScope<Object?>>(find.byWidgetPredicate((w) => w is PopScope<Object?>));
      expect(popScope.canPop, isFalse);
      popScope.onPopInvokedWithResult?.call(false, null);
      await tester.pumpAndSettle();

      expect(bottomBar(tester).active, AppTab.chats);
      // On Chats the shell is now poppable (returns to gallery in the preview).
      final popScopeOnChats = tester.widget<PopScope<Object?>>(find.byWidgetPredicate((w) => w is PopScope<Object?>));
      expect(popScopeOnChats.canPop, isTrue);
    });

    testWidgets('desktop titlebar subtitle tracks the active tab (R3 parity)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900)); // wide → rail + window titlebar
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const TabBarShell());
      await tester.pump(const Duration(milliseconds: 300)); // the chats tab fetches its page
      await tester.pumpAndSettle();

      String subtitle() => tester.widget<AppWindowTitlebarWidget>(find.byType(AppWindowTitlebarWidget)).subtitle!;

      // On the default Chats tab the strip reads the localized Chats label (like the mobile AppBar title).
      expect(subtitle(), l10nEn.chats);

      // Switch to Settings via the rail destination (disambiguated from the settings body's own text).
      await tester.tap(find.descendant(of: find.byType(AppNavigationRailWidget), matching: find.text(l10nEn.settings)));
      await tester.pumpAndSettle();

      // Regression guard: previously the subtitle was a hardcoded 'Chats' that never changed.
      expect(subtitle(), l10nEn.settings);
    });

    testWidgets('re-tapping the active Chats tab is a no-op that does not throw', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const TabBarShell());
      await tester.pump(const Duration(milliseconds: 300)); // the chats tab fetches its page
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(of: find.byType(AppBottomBarWidget), matching: find.text(l10nEn.chats)));
      await tester.pumpAndSettle();

      expect(bottomBar(tester).active, AppTab.chats);
      expect(tester.takeException(), isNull);
    });
  });
}
