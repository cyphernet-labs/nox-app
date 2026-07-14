import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/placeholder/route_placeholder_page.dart';
import 'package:nox_app/presentation/pages/set_username_page/bloc/set_username_bloc.dart';
import 'package:nox_app/presentation/pages/set_username_page/set_username_page.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  Finder doneButton() => find.widgetWithText(FilledButton, l10nEn.actionDone);

  testWidgets('is pre-filled with the default name and enables Done', (tester) async {
    await pumpApp(tester, const SetUsernamePage(demo: true));

    expect(find.text(SetUsernameBloc.defaultName), findsOneWidget);
    expect(tester.widget<FilledButton>(doneButton()).onPressed, isNotNull);
  });

  testWidgets('an invalid charset shows an error and disables Done', (tester) async {
    await pumpApp(tester, const SetUsernamePage(demo: true));

    await tester.enterText(find.byType(TextField), 'bad name!');
    await tester.pump();

    expect(find.text(l10nEn.usernameCharsetError), findsOneWidget);
    expect(tester.widget<FilledButton>(doneButton()).onPressed, isNull);
  });

  testWidgets('a taken name shows the taken error after the debounced check', (tester) async {
    await pumpApp(tester, const SetUsernamePage(demo: true), settle: false);

    await tester.enterText(find.byType(TextField), 'NOX');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text(l10nEn.nameTakenError), findsOneWidget);
  });

  testWidgets('Skip routes to the shell placeholder', (tester) async {
    await pumpApp(tester, const SetUsernamePage(demo: true));

    await tester.tap(find.widgetWithText(TextButton, l10nEn.actionSkip));
    await tester.pumpAndSettle();

    expect(find.byType(RoutePlaceholderPage), findsOneWidget);
  });
}
