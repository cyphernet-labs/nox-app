import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/pages/login_page/login_page.dart';
import 'package:nox_app/presentation/pages/placeholder/route_placeholder_page.dart';

import '../../../utils/pump_app.dart';

void main() {
  Finder signInButton() => find.widgetWithText(FilledButton, TextConstants.loginSignIn);

  testWidgets('Sign in is disabled when empty and enabled after typing', (tester) async {
    await pumpApp(tester, const LoginPage());

    expect(tester.widget<FilledButton>(signInButton()).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'some-identifier');
    await tester.pump();

    expect(tester.widget<FilledButton>(signInButton()).onPressed, isNotNull);
  });

  testWidgets('signing in with a new id routes to the set-username placeholder', (tester) async {
    await pumpApp(tester, const LoginPage());

    await tester.enterText(find.byType(TextField), 'fresh-identifier');
    await tester.pump();
    await tester.tap(signInButton());
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.byType(RoutePlaceholderPage), findsOneWidget);
    expect(find.text('Set username (2.3)'), findsOneWidget);
  });

  testWidgets('Scan QR opens a stubbed placeholder', (tester) async {
    await pumpApp(tester, const LoginPage());

    await tester.tap(find.widgetWithText(TextButton, TextConstants.loginScanQr));
    await tester.pumpAndSettle();

    expect(find.byType(RoutePlaceholderPage), findsOneWidget);
  });
}
