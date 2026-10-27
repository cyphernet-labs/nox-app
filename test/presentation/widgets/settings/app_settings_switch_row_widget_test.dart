import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_switch_row_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('renders title + supporting text and toggles', (tester) async {
    var current = false;
    await pumpApp(
      tester,
      StatefulBuilder(
        builder: (context, setState) => AppSettingsSwitchRowWidget(
          title: 'Push notifications',
          supportingText: 'Get notified about your chats.',
          value: current,
          onChanged: (value) => setState(() => current = value),
        ),
      ),
    );

    expect(find.text('Push notifications'), findsOneWidget);
    expect(find.text('Get notified about your chats.'), findsOneWidget);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(current, isTrue);
  });

  testWidgets('null onChanged renders a disabled row', (tester) async {
    await pumpApp(tester, const AppSettingsSwitchRowWidget(title: 'Push', value: false, onChanged: null));

    final row = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(row.onChanged, isNull);
  });
}
