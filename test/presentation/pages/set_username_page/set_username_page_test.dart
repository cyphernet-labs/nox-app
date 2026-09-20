import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/shell/tab_bar_shell_widget.dart';
import 'package:nox_app/presentation/pages/set_username_page/bloc/set_username_bloc.dart';
import 'package:nox_app/presentation/pages/set_username_page/set_username_page.dart';

import '../../../utils/fake_session_repository.dart';
import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
  });

  tearDown(() async {
    await getIt.reset();
  });

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

  testWidgets('a name that used to be reserved shows no error at all', (tester) async {
    // Person labels are not unique (owner, 2026-09-02) and nothing checks
    // them, so the screen has no "taken" state to reach. Four specific names
    // used to be refused here by a rule nothing else observed.
    await pumpApp(tester, const SetUsernamePage(demo: true), settle: false);

    await tester.enterText(find.byType(TextField), 'NOX');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text(l10nEn.nameTakenError), findsNothing);
  });

  testWidgets('Skip routes to the shell', (tester) async {
    await pumpApp(tester, const SetUsernamePage(demo: true));

    await tester.tap(find.widgetWithText(TextButton, l10nEn.actionSkip));
    await tester.pumpAndSettle();

    expect(find.byType(TabBarShell), findsOneWidget);
  });

  testWidgets('the real screen opens on the name the server assigned, in the FIELD', (tester) async {
    // The bloc test proves the state carries it. This proves the controller
    // follows: the field is built before the session read returns, so a prefill
    // that never reached the TextEditingController would leave the person
    // looking at an empty field while the state said otherwise.
    registerFakeSession(session: kTestSession.copyWith(label: 'Lena'));

    await pumpApp(tester, const SetUsernamePage());

    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, 'Lena');
    expect(find.text('Lena'), findsOneWidget);
    expect(tester.widget<FilledButton>(doneButton()).onPressed, isNotNull);
  });

  testWidgets('and stays empty when the session holds no name', (tester) async {
    registerFakeSession(session: kTestSession);

    await pumpApp(tester, const SetUsernamePage());

    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, isEmpty);
    expect(tester.widget<FilledButton>(doneButton()).onPressed, isNull, reason: 'Done must not submit an empty name');
  });
}
