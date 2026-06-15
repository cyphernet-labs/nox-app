import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/state/app_error_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  group('AppErrorWidget', () {
    testWidgets('shows the message and fires the retry callback', (tester) async {
      var taps = 0;
      await pumpApp(tester, AppErrorWidget(message: 'Boom', onTryAgain: () => taps++));

      expect(find.text('Boom'), findsOneWidget);
      await tester.tap(find.text(TextConstants.actionTryAgain));
      expect(taps, 1);
    });

    testWidgets('hides the retry CTA when no callback is given', (tester) async {
      await pumpApp(tester, const AppErrorWidget());

      expect(find.byType(FilledButton), findsNothing);
      expect(find.text(TextConstants.errorGeneralTitle), findsOneWidget);
    });
  });
}
