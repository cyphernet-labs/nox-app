import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/pages/about_page/about_body.dart';
import 'package:nox_app/presentation/pages/settings_root_page/settings_root_page.dart';
import 'package:nox_app/presentation/widgets/shell/app_navigation_rail_widget.dart';
import 'package:nox_app/presentation/widgets/shell/tab_bar_shell_widget.dart';

import '../../../utils/pump_app.dart';

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
    }

    testWidgets('renders an account avatar at the bottom of the rail', (tester) async {
      await pumpWide(tester);

      expect(find.byType(AppNavigationRailWidget), findsOneWidget);
      expect(find.byTooltip(TextConstants.settingsAccountTitle), findsOneWidget);
    });

    testWidgets('tapping the avatar switches to Settings and lands on the Account section', (tester) async {
      await pumpWide(tester);

      // Drive Settings to a non-Account section, then return to Chats, so the jump
      // has something to undo (proves it lands on Account, not just switches tabs).
      await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text(TextConstants.settings)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(TextConstants.settingsAboutTitle));
      await tester.pumpAndSettle();
      expect(find.byType(AboutBody), findsOneWidget);

      await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text(TextConstants.chats)));
      await tester.pumpAndSettle();

      // Tap the account avatar → Settings becomes active AND the section resets to Account.
      await tester.tap(find.byTooltip(TextConstants.settingsAccountTitle));
      await tester.pumpAndSettle();

      expect(settingsTabOpacity(tester), 1.0); // Settings tab is now the active one
      expect(find.byType(AboutBody), findsNothing); // jumped off the About section → back to Account
    });
  });

  group('TabBarShell account avatar (mobile)', () {
    testWidgets('no account avatar is shown in the bottom-bar layout', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpApp(tester, const TabBarShell());

      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(AppNavigationRailWidget), findsNothing);
      expect(find.byTooltip(TextConstants.settingsAccountTitle), findsNothing);
    });
  });
}
