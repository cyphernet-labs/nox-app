import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/about_page/about_body.dart';
import 'package:nox_app/presentation/pages/settings_root_page/settings_root_page.dart';
import 'package:nox_app/presentation/widgets/settings/app_identity_card_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_navigation_rail_widget.dart';
import 'package:nox_app/presentation/widgets/shell/tab_bar_shell_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  setUpAll(() async {
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async {
    await getIt.reset();
  });

  // Opacity of the shell tab that hosts [SettingsRootPage] (1.0 = active tab).
  double settingsTabOpacity(WidgetTester tester) {
    final opacity = tester.widget<AnimatedOpacity>(
      find.ancestor(of: find.byType(SettingsRootPage), matching: find.byType(AnimatedOpacity)).first,
    );
    return opacity.opacity;
  }

  group('TabBarShell account avatar (desktop rail)', () {
    Future<void> pumpWide(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const TabBarShell());
      await tester.pump(const Duration(milliseconds: 300)); // the chats tab fetches its page
      await tester.pumpAndSettle();
    }

    testWidgets('renders an account avatar at the bottom of the rail', (tester) async {
      await pumpWide(tester);

      expect(find.byType(AppNavigationRailWidget), findsOneWidget);
      expect(find.byTooltip(l10nEn.settingsAccountTitle), findsOneWidget);
    });

    testWidgets('tapping the avatar switches to Settings and lands on the Account section', (tester) async {
      await pumpWide(tester);

      // Drive Settings to a non-Account section, then return to Chats, so the jump
      // has something to undo (proves it lands on Account, not just switches tabs).
      await tester.tap(find.descendant(of: find.byType(AppNavigationRailWidget), matching: find.text(l10nEn.settings)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10nEn.settingsAboutTitle));
      await tester.pumpAndSettle();
      expect(find.byType(AboutBody), findsOneWidget);

      await tester.tap(find.descendant(of: find.byType(AppNavigationRailWidget), matching: find.text(l10nEn.chats)));
      await tester.pumpAndSettle();

      // Tap the account avatar → Settings becomes active AND the section resets to Account.
      await tester.tap(find.byTooltip(l10nEn.settingsAccountTitle));
      await tester.pumpAndSettle();

      expect(settingsTabOpacity(tester), 1.0); // Settings tab is now the active one
      expect(find.byType(AboutBody), findsNothing); // left the About section
      // Positively landed on Account: its detail (the identity card) is now built.
      expect(find.byType(AppIdentityCardWidget), findsOneWidget);
    });
  });

  group('TabBarShell account avatar (mobile, N4)', () {
    Future<void> pumpNarrow(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const TabBarShell());
      await tester.pump(const Duration(milliseconds: 300)); // the chats tab fetches its page
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
    }

    testWidgets('renders an account avatar in the chats app bar (no rail)', (tester) async {
      await pumpNarrow(tester);

      expect(find.byType(AppNavigationRailWidget), findsNothing); // no rail on mobile
      expect(find.byTooltip(l10nEn.settingsAccountTitle), findsOneWidget); // the app-bar avatar (N4)
    });

    testWidgets('tapping the avatar switches to the Settings tab (Account card at the top of the list)', (tester) async {
      await pumpNarrow(tester);
      expect(settingsTabOpacity(tester), 0.0); // Chats starts active, Settings inactive

      await tester.tap(find.byTooltip(l10nEn.settingsAccountTitle));
      await tester.pumpAndSettle();

      expect(settingsTabOpacity(tester), 1.0); // Settings tab is now active
      // Mobile Settings is a flat list with the Account identity card pinned at the top,
      // so landing on the Settings tab lands the user on Account (the jump is a no-op there).
      expect(find.byType(AppIdentityCardWidget), findsWidgets);
    });
  });
}
