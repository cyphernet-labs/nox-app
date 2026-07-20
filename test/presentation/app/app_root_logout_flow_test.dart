import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/app/app_root.dart';
import 'package:nox_app/presentation/widgets/shell/tab_bar_shell_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Seed a fully authorized session (identifier present + onboarding complete).
    FlutterSecureStorage.setMockInitialValues({'session.identifier': 'registered'});
    SharedPreferences.setMockInitialValues({'session.onboarding_complete': true});
    await configureDependencies(Environment.test);
    await getIt.allReady();
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('a stored authorized session resumes straight into the shell after restart', (tester) async {
    await tester.pumpWidget(const AppRoot());
    await tester.pumpAndSettle();
    expect(find.byType(TabBarShell), findsOneWidget);
    expect(find.text(l10nEn.loginSignIn), findsNothing);
  });

  testWidgets('logout wipes the session and the spine returns to Login', (tester) async {
    await tester.pumpWidget(const AppRoot());
    await tester.pumpAndSettle();
    expect(find.byType(TabBarShell), findsOneWidget);

    // logout() now wipes the chat/message Sembast caches (real DB I/O), so run it in
    // the real async zone; a fake-async `await` would hang on the DB timers.
    await tester.runAsync(() => getIt<AuthRepository>().logout());
    await tester.pumpAndSettle();

    expect(find.text(l10nEn.loginSignIn), findsOneWidget);
    expect(find.byType(TabBarShell), findsNothing);
  });
}
