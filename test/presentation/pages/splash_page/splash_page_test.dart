import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/presentation/pages/placeholder/route_placeholder_page.dart';
import 'package:nox_app/presentation/pages/splash_page/splash_page.dart';
import 'package:nox_app/presentation/widgets/shell/app_wordmark_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('Splash renders the brand logo + wordmark on the brand-fixed dark canvas', (tester) async {
    await pumpApp(tester, const SplashPage(), settle: false);

    // Logo image + the NOX wordmark are in the reveal group.
    expect(find.byType(Image), findsWidgets);
    expect(find.byType(AppWordmarkWidget), findsOneWidget);

    // Background is the brand canvas, independent of theme (SplashPage's own Scaffold,
    // not pumpApp's outer wrapper).
    final scaffold = tester.widget<Scaffold>(find.descendant(of: find.byType(SplashPage), matching: find.byType(Scaffold)));
    expect(scaffold.backgroundColor, NoxBrand.canvasDark);
  });

  testWidgets('Splash stays put until an outcome is chosen, then routes', (tester) async {
    await pumpApp(tester, const SplashPage(), settle: false);
    await tester.pump(NoxDuration.splashIn); // finish the reveal

    // Reveal done but no outcome chosen yet → no navigation.
    expect(find.byType(RoutePlaceholderPage), findsNothing);

    await tester.tap(find.text('Has ID'));
    await tester.pumpAndSettle();

    expect(find.byType(RoutePlaceholderPage), findsOneWidget);
  });

  testWidgets('Splash routes the error outcome (placeholder until 3.1 lands)', (tester) async {
    await pumpApp(tester, const SplashPage(), settle: false);
    await tester.pump(NoxDuration.splashIn);

    await tester.tap(find.text('Error'));
    await tester.pumpAndSettle();

    expect(find.byType(RoutePlaceholderPage), findsOneWidget);
    expect(find.text('Error (3.1)'), findsOneWidget);
  });
}
