import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/pages/error_page/error_page.dart';
import 'package:nox_app/presentation/pages/placeholder/route_placeholder_page.dart';
import 'package:nox_app/presentation/pages/qr_scan_page/qr_scan_page.dart';
import 'package:nox_app/presentation/widgets/qr/app_qr_overlay_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  testWidgets('shows the scanning overlay, manual entry and camera actions', (tester) async {
    await pumpApp(tester, const QrScanPage(demo: true));

    expect(find.byType(AppQrOverlayWidget), findsOneWidget);
    expect(find.text(TextConstants.qrEnterManually), findsOneWidget);
    expect(find.byTooltip(TextConstants.tooltipFlashlight), findsOneWidget);
    expect(find.byTooltip(TextConstants.tooltipSwitchCamera), findsOneWidget);
  });

  testWidgets('debug control switches to the permission-denied panel', (tester) async {
    await pumpApp(tester, const QrScanPage(demo: true));

    await tester.tap(find.widgetWithText(OutlinedButton, 'denied'));
    await tester.pump();

    expect(find.text(TextConstants.qrPermissionTitle), findsOneWidget);
    expect(find.text(TextConstants.qrPermissionMessage), findsOneWidget);
    expect(find.text(TextConstants.actionOpenSettings), findsOneWidget);
  });

  testWidgets('an invalid QR shows a snackbar and keeps scanning', (tester) async {
    await pumpApp(tester, const QrScanPage(demo: true));

    await tester.tap(find.widgetWithText(OutlinedButton, 'invalid'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.text(TextConstants.qrInvalidSnackbar), findsOneWidget);
    expect(find.byType(AppQrOverlayWidget), findsOneWidget);
  });

  testWidgets('a successful scan routes to the login auto-submit placeholder', (tester) async {
    await pumpApp(tester, const QrScanPage(demo: true));

    await tester.tap(find.widgetWithText(OutlinedButton, 'success'));
    await tester.pumpAndSettle();

    expect(find.byType(RoutePlaceholderPage), findsOneWidget);
  });

  testWidgets('a fatal camera error routes to the universal error screen', (tester) async {
    await pumpApp(tester, const QrScanPage(demo: true));

    await tester.tap(find.widgetWithText(OutlinedButton, 'fatal'));
    await tester.pumpAndSettle();

    expect(find.byType(AppErrorPage), findsOneWidget);
  });

  testWidgets('toggling the torch does not throw', (tester) async {
    await pumpApp(tester, const QrScanPage(demo: true));

    await tester.tap(find.byTooltip(TextConstants.tooltipFlashlight));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
