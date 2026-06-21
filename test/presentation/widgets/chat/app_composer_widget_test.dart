import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/chat/app_composer_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  group('AppComposerWidget', () {
    testWidgets('shows the hint when empty', (tester) async {
      await pumpApp(tester, AppComposerWidget(controller: TextEditingController()));

      expect(find.text(TextConstants.composerHint), findsOneWidget);
    });

    testWidgets('send is disabled until there is text (reactive to the controller)', (tester) async {
      var sends = 0;
      await pumpApp(tester, AppComposerWidget(controller: TextEditingController(), onSend: () => sends++));

      await tester.tap(find.byType(IconButton).last);
      expect(sends, 0); // empty → inactive

      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pump();
      await tester.tap(find.byType(IconButton).last);
      expect(sends, 1); // text present → active
    });

    testWidgets('send is active when an attachment is staged even with empty text', (tester) async {
      var sends = 0;
      await pumpApp(
        tester,
        AppComposerWidget(controller: TextEditingController(), attachment: const SizedBox(width: 10, height: 10), onSend: () => sends++),
      );

      await tester.tap(find.byType(IconButton).last);
      expect(sends, 1);
    });

    testWidgets('fires onAttach', (tester) async {
      var attaches = 0;
      await pumpApp(tester, AppComposerWidget(controller: TextEditingController(), onAttach: () => attaches++));

      await tester.tap(find.byType(IconButton).first);
      expect(attaches, 1);
    });

    testWidgets('typing updates the field', (tester) async {
      await pumpApp(tester, AppComposerWidget(controller: TextEditingController()));

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();

      expect(find.text('hello'), findsOneWidget);
    });
  });
}
