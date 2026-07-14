import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/qr_scanner_capability.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/pages/login_page/login_page.dart';
import 'package:nox_app/presentation/pages/placeholder/route_placeholder_page.dart';
import 'package:nox_app/presentation/pages/qr_scan_page/qr_scan_page.dart';

import '../../../utils/pump_app.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  Finder signInButton() => find.widgetWithText(FilledButton, l10nEn.loginSignIn);

  testWidgets('Sign in is disabled when empty and enabled after typing', (tester) async {
    await pumpApp(tester, const LoginPage(demo: true));

    expect(tester.widget<FilledButton>(signInButton()).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'some-identifier');
    await tester.pump();

    expect(tester.widget<FilledButton>(signInButton()).onPressed, isNotNull);
  });

  testWidgets('signing in with a new id routes to the set-username placeholder', (tester) async {
    await pumpApp(tester, const LoginPage(demo: true));

    await tester.enterText(find.byType(TextField), 'fresh-identifier');
    await tester.pump();
    await tester.tap(signInButton());
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.byType(RoutePlaceholderPage), findsOneWidget);
    expect(find.text('Set username (2.3)'), findsOneWidget);
  });

  testWidgets('Scan QR opens the QR scanner (2.2) where the scanner exists', (tester) async {
    addTearDown(() => QrScannerCapability.debugOverride = null);
    QrScannerCapability.debugOverride = true;
    await pumpApp(tester, const LoginPage(demo: true));

    expect(find.widgetWithText(TextButton, l10nEn.loginScanQr), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, l10nEn.loginScanQr));
    await tester.pumpAndSettle();

    expect(find.byType(QrScanPage), findsOneWidget);
  });

  testWidgets('Scan QR is hidden on platforms without a scanner (Windows/Linux, FR-016)', (tester) async {
    addTearDown(() => QrScannerCapability.debugOverride = null);
    QrScannerCapability.debugOverride = false;
    await pumpApp(tester, const LoginPage(demo: true));

    expect(find.widgetWithText(TextButton, l10nEn.loginScanQr), findsNothing);
  });
}
