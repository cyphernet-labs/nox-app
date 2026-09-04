import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/app/app_root.dart';
import 'package:nox_app/presentation/pages/set_username_page/set_username_page.dart';
import 'package:nox_app/presentation/widgets/shell/tab_bar_shell_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt.allReady();
  });

  tearDown(() async {
    await getIt.reset();
  });

  Future<void> bootToLogin(WidgetTester tester) async {
    await tester.pumpWidget(const AppRoot());
    await tester.pumpAndSettle();
    expect(find.text(l10nEn.loginSignIn), findsOneWidget);
  }

  Future<void> signIn(WidgetTester tester, String id) async {
    await tester.enterText(find.byType(TextField).first, id);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, l10nEn.loginSignIn));
    await tester.pumpAndSettle();
  }

  // A link the Go server actually produced, captured from a live noxd.
  const link = 'https://nox.app/p/#AQF_AAABH5CjZmMytIk_2XvPJ-jonqlQtYsZD3SB33P1foxqnrVbFo-VEf6WohQoqA1_na5iVUo';

  testWidgets('presenting a pairing link lands on Set username, stack cleared', (tester) async {
    // No live channel in this environment, so there is no server to ask and
    // the naming screen is due - which is what makes the decision honest
    // rather than guessed from a hardcoded list, as it once was.
    await bootToLogin(tester);
    await signIn(tester, link);
    expect(find.byType(SetUsernamePage), findsOneWidget);
    expect(find.text(l10nEn.loginSignIn), findsNothing);
  });

  testWidgets('a string that is not a pairing link goes nowhere', (tester) async {
    await bootToLogin(tester);
    await signIn(tester, 'registered');
    // 'registered' used to skip onboarding by being one of two hardcoded
    // strings. It is not a link, so now it is simply unreadable.
    expect(find.byType(SetUsernamePage), findsNothing);
    expect(find.byType(TabBarShell), findsNothing);
    expect(find.text(l10nEn.loginSignIn), findsOneWidget);
  });
}
