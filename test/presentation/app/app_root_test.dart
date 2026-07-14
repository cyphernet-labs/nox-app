import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/app/app_root.dart';
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

  testWidgets('cold start with no stored session lands on Login after the splash', (tester) async {
    await tester.pumpWidget(const AppRoot());

    // First frame: the app state resolves but the first navigation is held behind
    // the splash reveal — Login is not shown yet.
    await tester.pump();
    expect(find.text(l10nEn.loginSignIn), findsNothing);

    // Let the reveal finish; the splash releases the first navigation.
    await tester.pumpAndSettle();
    expect(find.text(l10nEn.loginSignIn), findsOneWidget);
  });
}
