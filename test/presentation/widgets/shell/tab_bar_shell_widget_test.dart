import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/pages/create_chat_page/create_chat_page.dart';
import 'package:nox_app/presentation/pages/placeholder/chats_placeholder_page.dart';
import 'package:nox_app/presentation/pages/placeholder/settings_placeholder_page.dart';
import 'package:nox_app/presentation/widgets/shell/app_bottom_bar_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_create_fab_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_navigation_rail_widget.dart';
import 'package:nox_app/presentation/widgets/shell/tab_bar_shell_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  group('TabBarShell', () {
    AppBottomBarWidget bottomBar(WidgetTester tester) => tester.widget<AppBottomBarWidget>(find.byType(AppBottomBarWidget));

    testWidgets('narrow window shows the bottom bar + docked FAB, not the rail', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const TabBarShell());

      expect(find.byType(AppBottomBarWidget), findsOneWidget);
      expect(find.byType(AppCreateFabWidget), findsOneWidget);
      expect(find.byType(AppNavigationRailWidget), findsNothing);
    });

    testWidgets('wide window shows the navigation rail, not the bottom bar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const TabBarShell());

      expect(find.byType(AppNavigationRailWidget), findsOneWidget);
      expect(find.byType(AppBottomBarWidget), findsNothing);
    });

    testWidgets('keeps both tab bodies in the tree (state preserved) and switches the active tab', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const TabBarShell());

      // Both bodies are always mounted (IndexedStack-like preservation, FR-021).
      expect(find.byType(ChatsPlaceholderPage), findsOneWidget);
      expect(find.byType(SettingsPlaceholderPage), findsOneWidget);
      expect(bottomBar(tester).active, AppTab.chats);

      await tester.tap(find.descendant(of: find.byType(AppBottomBarWidget), matching: find.text(TextConstants.settings)));
      await tester.pumpAndSettle();

      expect(bottomBar(tester).active, AppTab.settings);
      // Bodies still both mounted after the switch.
      expect(find.byType(ChatsPlaceholderPage), findsOneWidget);
      expect(find.byType(SettingsPlaceholderPage), findsOneWidget);
    });

    testWidgets('central + opens the real Create chat (6.1)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const TabBarShell());

      await tester.tap(find.byType(AppCreateFabWidget));
      await tester.pumpAndSettle();

      expect(find.byType(CreateChatPage), findsOneWidget);
    });

    testWidgets('system back on a non-Chats tab returns to Chats instead of popping the shell', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const TabBarShell());

      // Go to Settings.
      await tester.tap(find.descendant(of: find.byType(AppBottomBarWidget), matching: find.text(TextConstants.settings)));
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

    testWidgets('re-tapping the active Chats tab is a no-op that does not throw', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const TabBarShell());

      await tester.tap(find.descendant(of: find.byType(AppBottomBarWidget), matching: find.text(TextConstants.chats)));
      await tester.pumpAndSettle();

      expect(bottomBar(tester).active, AppTab.chats);
      expect(tester.takeException(), isNull);
    });
  });
}
