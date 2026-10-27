import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/helpers/app_feedback_helper.dart';

import '../../utils/pump_app.dart';

void main() {
  group('app feedback helpers', () {
    testWidgets('showAppSnackBar shows a SnackBar with the text', (tester) async {
      await pumpApp(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppSnackBar(context, text: 'Saved'),
            child: const Text('go'),
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('showAppSnackBar with error applies the error color override', (tester) async {
      late ColorScheme colorScheme;
      await pumpApp(
        tester,
        Builder(
          builder: (context) {
            colorScheme = Theme.of(context).colorScheme;
            return TextButton(
              onPressed: () => showAppSnackBar(context, text: 'Failed', error: true),
              child: const Text('go'),
            );
          },
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pump();

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.backgroundColor, colorScheme.errorContainer);

      final content = tester.widget<Text>(find.text('Failed'));
      expect(content.style?.color, colorScheme.onErrorContainer);
    });

    testWidgets('showAppBanner shows a MaterialBanner with the text', (tester) async {
      await pumpApp(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppBanner(context, text: 'No connection'),
            child: const Text('go'),
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pump();

      expect(find.byType(MaterialBanner), findsOneWidget);
      expect(find.text('No connection'), findsOneWidget);
    });

    testWidgets('showAppBanner action dismisses the banner and then runs onAction', (tester) async {
      var actionRan = false;
      await pumpApp(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppBanner(
              context,
              text: 'No connection',
              actionLabel: 'Retry',
              // A no-op handler: the helper itself must dismiss the banner, not the callback.
              onAction: () => actionRan = true,
            ),
            child: const Text('go'),
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle(); // let the banner finish entering so the action is on-screen
      expect(find.byType(MaterialBanner), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      // The dismiss is queued by the helper (hideCurrentMaterialBanner) before onAction,
      // so the banner is gone even though the callback never touches it, and onAction ran.
      expect(actionRan, isTrue);
      expect(find.byType(MaterialBanner), findsNothing);
    });
  });
}
