import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/pages/create_chat_page/create_chat_page.dart';

import '../../../utils/pump_app.dart';

void main() {
  Finder createButton() => find.widgetWithText(FilledButton, TextConstants.actionCreate);

  testWidgets('mobile: empty disables Create, a free name enables it', (tester) async {
    await pumpApp(tester, const CreateChatPage(), settle: false);

    expect(tester.widget<FilledButton>(createButton()).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Fresh chat');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(tester.widget<FilledButton>(createButton()).onPressed, isNotNull);
  });

  testWidgets('mobile: a taken name shows the taken error', (tester) async {
    await pumpApp(tester, const CreateChatPage(), settle: false);

    await tester.enterText(find.byType(TextField), 'General');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text(TextConstants.nameTakenError), findsOneWidget);
  });

  testWidgets('desktop: renders a modal dialog with Cancel and Create', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpApp(tester, const CreateChatPage(), settle: false);

    expect(find.widgetWithText(TextButton, TextConstants.actionCancel), findsOneWidget);
    expect(find.widgetWithText(FilledButton, TextConstants.actionCreate), findsOneWidget);
  });
}
