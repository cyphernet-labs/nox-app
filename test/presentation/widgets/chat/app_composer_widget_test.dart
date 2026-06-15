import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/chat/app_composer_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  group('AppComposerWidget', () {
    testWidgets('shows the hint when empty', (tester) async {
      await pumpApp(tester, const AppComposerWidget());

      expect(find.text(TextConstants.composerHint), findsOneWidget);
    });

    testWidgets('send is disabled until sendActive', (tester) async {
      var sends = 0;
      await pumpApp(tester, AppComposerWidget(onSend: () => sends++));
      await tester.tap(find.byType(IconButton).last);
      expect(sends, 0); // inactive

      await pumpApp(tester, AppComposerWidget(value: 'hi', sendActive: true, onSend: () => sends++));
      await tester.tap(find.byType(IconButton).last);
      expect(sends, 1); // active
    });

    testWidgets('fires onAttach', (tester) async {
      var attaches = 0;
      await pumpApp(tester, AppComposerWidget(onAttach: () => attaches++));

      await tester.tap(find.byType(IconButton).first);
      expect(attaches, 1);
    });
  });
}
