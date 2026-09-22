import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_nav_row_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  group('AppSettingsNavRowWidget', () {
    testWidgets('renders the title and fires onTap', (tester) async {
      var tapped = false;
      await pumpApp(tester, AppSettingsNavRowWidget(title: 'Notifications', icon: NoxIcons.notifications, onTap: () => tapped = true));

      expect(find.text('Notifications'), findsOneWidget);
      await tester.tap(find.byType(AppSettingsNavRowWidget));
      expect(tapped, isTrue);
    });

    testWidgets('a phone tile leads with a chip and ends with a chevron', (tester) async {
      await pumpApp(tester, AppSettingsNavRowWidget(title: 'Devices', icon: NoxIcons.devices, onTap: () {}));

      final tile = tester.widget<ListTile>(find.byType(ListTile));
      expect(tile.leading, isNotNull);
      expect(tile.trailing, isNotNull);
    });

    testWidgets('the destructive row is error throughout, and has no chevron', (tester) async {
      // No chevron by design: Log out opens a dialog rather than navigating, and
      // a chevron would promise otherwise.
      await pumpApp(tester, AppSettingsNavRowWidget(title: 'Log out', icon: NoxIcons.logoutFill, danger: true, onTap: () {}));

      final context = tester.element(find.byType(AppSettingsNavRowWidget));
      final error = Theme.of(context).colorScheme.error;
      expect(tester.widget<Text>(find.text('Log out')).style?.color, error);
      expect(tester.widget<AppIconWidget>(find.byType(AppIconWidget)).color, error);
      expect(tester.widget<ListTile>(find.byType(ListTile)).trailing, isNull);
    });

    testWidgets('a selected pane item swaps its glyph for the filled variant', (tester) async {
      // The same FILL axis the bottom bar swaps on its tabs.
      await pumpApp(
        tester,
        AppSettingsNavRowWidget(
          title: 'Account',
          icon: NoxIcons.person,
          selectedIcon: NoxIcons.personFill,
          selected: true,
          menuPane: true,
          onTap: () {},
        ),
      );

      expect(tester.widget<AppIconWidget>(find.byType(AppIconWidget)).icon, NoxIcons.personFill);
    });

    testWidgets('an unselected pane item keeps the outlined glyph', (tester) async {
      await pumpApp(
        tester,
        AppSettingsNavRowWidget(title: 'Account', icon: NoxIcons.person, selectedIcon: NoxIcons.personFill, menuPane: true, onTap: () {}),
      );

      expect(tester.widget<AppIconWidget>(find.byType(AppIconWidget)).icon, NoxIcons.person);
    });
  });
}
