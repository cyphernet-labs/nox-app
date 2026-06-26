import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/app/app_root.dart';
import 'package:nox_app/presentation/widgets/shell/tab_bar_shell_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    expect(find.text(TextConstants.loginSignIn), findsNothing);
  });

  testWidgets('logout wipes the session and the spine returns to Login', (tester) async {
    await tester.pumpWidget(const AppRoot());
    await tester.pumpAndSettle();
    expect(find.byType(TabBarShell), findsOneWidget);

    await getIt<AuthRepository>().logout();
    await tester.pumpAndSettle();

    expect(find.text(TextConstants.loginSignIn), findsOneWidget);
    expect(find.byType(TabBarShell), findsNothing);
  });
}
