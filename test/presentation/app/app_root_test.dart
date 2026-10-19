import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/design/app_overlay_style_tokens.dart';
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

  testWidgets('the system bars follow the theme on every screen, the splash its own dark style', (tester) async {
    Iterable<SystemUiOverlayStyle> regions() => tester
        .widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(find.byWidgetPredicate((w) => w is AnnotatedRegion<SystemUiOverlayStyle>))
        .map((r) => r.value);

    await tester.pumpWidget(const AppRoot());
    await tester.pump();
    expect(regions(), contains(AppOverlayStyleTokens.splash), reason: 'the splash is brand-fixed dark');

    await tester.pumpAndSettle();
    expect(regions(), isNot(contains(AppOverlayStyleTokens.splash)), reason: 'the splash is gone');
    final scheme = Theme.of(tester.element(find.text(l10nEn.loginSignIn))).colorScheme;
    final theme = AppOverlayStyleTokens.of(scheme);
    expect(regions(), contains(theme));
    // The theme is light here: dark icons on both bars, and the navigation
    // bar back from the splash's dark one.
    expect(theme.statusBarIconBrightness, Brightness.dark);
    expect(theme.systemNavigationBarIconBrightness, Brightness.dark);
    expect(theme.systemNavigationBarColor, scheme.surfaceContainer);
  });
}
