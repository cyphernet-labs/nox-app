import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/settings/app_logout_dialog_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  group('AppLogoutDialogWidget', () {
    testWidgets('Cancel resolves to false', (tester) async {
      bool? result;
      await pumpApp(
        tester,
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(onPressed: () async => result = await AppLogoutDialogWidget.show(context), child: const Text('open')),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(TextConstants.logoutDialogTitle), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, TextConstants.actionCancel));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('Confirm shows a spinner then resolves to true', (tester) async {
      bool? result;
      await pumpApp(
        tester,
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(onPressed: () async => result = await AppLogoutDialogWidget.show(context), child: const Text('open')),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, TextConstants.logoutRow));
      await tester.pump(); // loading frame — the confirm button now shows the spinner instead of its label
      expect(find.descendant(of: find.byType(TextButton), matching: find.byType(CircularProgressIndicator)), findsOneWidget);

      await tester.pumpAndSettle();
      expect(result, isTrue);
    });
  });
}
