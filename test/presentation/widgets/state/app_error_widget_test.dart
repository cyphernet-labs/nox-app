import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/state/app_error_widget.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  group('AppErrorWidget', () {
    testWidgets('shows the message and fires the retry callback', (tester) async {
      var taps = 0;
      await pumpApp(tester, AppErrorWidget(message: 'Boom', onTryAgain: () => taps++));

      expect(find.text('Boom'), findsOneWidget);
      await tester.tap(find.text(l10nEn.actionTryAgain));
      expect(taps, 1);
    });

    testWidgets('hides the retry CTA when no callback is given', (tester) async {
      await pumpApp(tester, const AppErrorWidget());

      expect(find.byType(FilledButton), findsNothing);
      expect(find.text(l10nEn.errorGeneralTitle), findsOneWidget);
    });
  });
}
