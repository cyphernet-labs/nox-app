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
  });
}
