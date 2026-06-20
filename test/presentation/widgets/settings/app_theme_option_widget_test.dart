import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_theme_option_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('renders the label and a check glyph when selected', (tester) async {
    var tapped = false;
    await pumpApp(
      tester,
      AppThemeOptionWidget(label: 'Dark', preview: const SizedBox(width: 48, height: 36), selected: true, onTap: () => tapped = true),
    );

    expect(find.text('Dark'), findsOneWidget);
    expect(find.byType(AppIconWidget), findsOneWidget); // the check
    await tester.tap(find.text('Dark'));
    expect(tapped, isTrue);
  });

  testWidgets('shows no check when not selected', (tester) async {
    await pumpApp(
      tester,
      AppThemeOptionWidget(label: 'Light', preview: const SizedBox(width: 48, height: 36), selected: false, onTap: () {}),
    );

    expect(find.byType(AppIconWidget), findsNothing);
  });
}
