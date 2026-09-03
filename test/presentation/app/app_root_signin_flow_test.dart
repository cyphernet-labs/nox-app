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

  testWidgets('signing in with a new identifier lands on Set username, stack cleared', (tester) async {
    await bootToLogin(tester);
    await signIn(tester, 'brand-new-id');
    expect(find.byType(SetUsernamePage), findsOneWidget);
    expect(find.text(l10nEn.loginSignIn), findsNothing);
  });

  testWidgets('no identifier is special any more - every sign-in without a server onboards', (tester) async {
    // 'registered' used to skip onboarding by being one of two hardcoded
    // strings. The server decides now, and this environment has no live
    // channel to ask, so the naming screen is due - which is what makes the
    // decision honest rather than guessed.
    await bootToLogin(tester);
    await signIn(tester, 'registered');
    expect(find.byType(SetUsernamePage), findsOneWidget);
    expect(find.byType(TabBarShell), findsNothing);
  });
}
