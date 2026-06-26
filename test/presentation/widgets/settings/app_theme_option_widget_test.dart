import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/settings/app_theme_option_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('renders the label + caption and is tappable when selected', (tester) async {
    var tapped = false;
    await pumpApp(
      tester,
      AppThemeOptionWidget(
        label: 'Dark',
        caption: 'Always dark',
        preview: const SizedBox(width: 48, height: 36),
        selected: true,
        onTap: () => tapped = true,
      ),
    );

    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Always dark'), findsOneWidget);
    // Selection indicator (the always-present radio dot + fill) is golden-covered.
    await tester.tap(find.text('Dark'));
    expect(tapped, isTrue);
  });

  testWidgets('renders the label when not selected', (tester) async {
    await pumpApp(
      tester,
      AppThemeOptionWidget(label: 'Light', preview: const SizedBox(width: 48, height: 36), selected: false, onTap: () {}),
    );

    expect(find.text('Light'), findsOneWidget);
  });
}
