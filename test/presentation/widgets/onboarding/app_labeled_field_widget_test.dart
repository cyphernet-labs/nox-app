import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_labeled_field_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_spinner_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  testWidgets('shows label, counter and error text', (tester) async {
    final controller = TextEditingController(text: 'abc');
    addTearDown(controller.dispose);

    await pumpApp(
      tester,
      AppLabeledFieldWidget(controller: controller, label: l10nEn.usernameLabel, maxLength: 32, errorText: l10nEn.nameTakenError),
    );

    expect(find.text(l10nEn.usernameLabel), findsWidgets);
    expect(find.text(l10nEn.nameTakenError), findsOneWidget);
    expect(find.text('3/32'), findsOneWidget);
  });

  testWidgets('forwards onChanged', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    String? last;

    await pumpApp(
      tester,
      AppLabeledFieldWidget(controller: controller, label: l10nEn.createChatNameLabel, maxLength: 64, onChanged: (value) => last = value),
    );

    await tester.enterText(find.byType(TextField), 'hi');
    expect(last, 'hi');
  });

  testWidgets('shows the suffix spinner while checking availability', (tester) async {
    final controller = TextEditingController(text: 'name');
    addTearDown(controller.dispose);

    await pumpApp(
      tester,
      AppLabeledFieldWidget(controller: controller, label: l10nEn.usernameLabel, maxLength: 32, checking: true),
      settle: false,
    );

    expect(find.byType(AppSpinnerWidget), findsOneWidget);
  });
}
