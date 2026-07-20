import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/app/app_root.dart';
import 'package:shared_preferences/shared_preferences.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Seed an authorized session so we can force-logout from it.
    FlutterSecureStorage.setMockInitialValues({'session.identifier': 'registered'});
    SharedPreferences.setMockInitialValues({'session.onboarding_complete': true});
    await configureDependencies(Environment.test);
    await getIt.allReady();
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('forced logout shows the session-expired message once over Login', (tester) async {
    await tester.pumpWidget(const AppRoot());
    await tester.pumpAndSettle();

    // logout() wipes the chat/message Sembast caches (real DB I/O) → run in the real
    // async zone, else a fake-async await hangs on the DB timers.
    await tester.runAsync(() => getIt<AuthRepository>().logout(forced: true));
    await tester.pump(); // app-state apply + routing push
    await tester.pump(); // post-frame callback → showSnackBar
    await tester.pump(const Duration(milliseconds: 200)); // snackbar enters (mid route-transition)
    // Settle past the route transition: mid-transition both the outgoing and incoming
    // Scaffolds briefly render the same app-level snackbar, so we assert once the push
    // has fully replaced the stack (exactly one snackbar over Login).
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(l10nEn.sessionExpiredMessage), findsOneWidget);
    expect(find.text(l10nEn.loginSignIn), findsOneWidget);

    // Drain the snackbar auto-dismiss timer to avoid a pending-timer failure.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('ordinary logout returns to Login without the session-expired message', (tester) async {
    await tester.pumpWidget(const AppRoot());
    await tester.pumpAndSettle();

    await tester.runAsync(() => getIt<AuthRepository>().logout());
    await tester.pumpAndSettle();

    expect(find.text(l10nEn.loginSignIn), findsOneWidget);
    expect(find.text(l10nEn.sessionExpiredMessage), findsNothing);
  });
}
