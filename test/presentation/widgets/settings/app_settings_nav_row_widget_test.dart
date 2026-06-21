import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_nav_row_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  group('AppSettingsNavRowWidget', () {
    testWidgets('renders the title and fires onTap', (tester) async {
      var tapped = false;
      await pumpApp(tester, AppSettingsNavRowWidget(title: 'Notifications', onTap: () => tapped = true));

      expect(find.text('Notifications'), findsOneWidget);
      await tester.tap(find.byType(AppSettingsNavRowWidget));
      expect(tapped, isTrue);
    });

    testWidgets('applies the destructive color to the title', (tester) async {
      await pumpApp(tester, AppSettingsNavRowWidget(title: 'Log out', onTap: () {}, color: const Color(0xFFB00020)));

      final tile = tester.widget<ListTile>(find.byType(ListTile));
      expect(tile.textColor, const Color(0xFFB00020));
    });
  });
}
