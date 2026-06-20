import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/pages/placeholder/route_placeholder_page.dart';
import 'package:nox_app/presentation/pages/set_username_page/bloc/set_username_bloc.dart';
import 'package:nox_app/presentation/pages/set_username_page/set_username_page.dart';

import '../../../utils/pump_app.dart';

void main() {
  Finder doneButton() => find.widgetWithText(FilledButton, TextConstants.actionDone);

  testWidgets('is pre-filled with the default name and enables Done', (tester) async {
    await pumpApp(tester, const SetUsernamePage());

    expect(find.text(SetUsernameBloc.defaultName), findsOneWidget);
    expect(tester.widget<FilledButton>(doneButton()).onPressed, isNotNull);
  });

  testWidgets('an invalid charset shows an error and disables Done', (tester) async {
    await pumpApp(tester, const SetUsernamePage());

    await tester.enterText(find.byType(TextField), 'bad name!');
    await tester.pump();

    expect(find.text(TextConstants.usernameCharsetError), findsOneWidget);
    expect(tester.widget<FilledButton>(doneButton()).onPressed, isNull);
  });

  testWidgets('a taken name shows the taken error after the debounced check', (tester) async {
    await pumpApp(tester, const SetUsernamePage(), settle: false);

    await tester.enterText(find.byType(TextField), 'NOX');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text(TextConstants.nameTakenError), findsOneWidget);
  });

  testWidgets('Skip routes to the shell placeholder', (tester) async {
    await pumpApp(tester, const SetUsernamePage());

    await tester.tap(find.widgetWithText(TextButton, TextConstants.actionSkip));
    await tester.pumpAndSettle();

    expect(find.byType(RoutePlaceholderPage), findsOneWidget);
  });
}
