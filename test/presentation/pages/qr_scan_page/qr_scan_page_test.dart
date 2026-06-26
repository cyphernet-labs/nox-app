import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nox_app/domain/model/qr/camera_permission_status.dart';
import 'package:nox_app/general/nox_qr_envelope.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/pages/qr_scan_page/bloc/qr_scan_bloc.dart';
import 'package:nox_app/presentation/pages/qr_scan_page/qr_scan_page.dart';
import 'package:nox_app/presentation/widgets/qr/app_qr_overlay_widget.dart';

import '../../../utils/pump_app.dart';

void main() {
  group('demo (gallery) controls', () {
    testWidgets('opens on the scanning overlay with manual entry and camera actions', (tester) async {
      await pumpApp(tester, const QrScanPage(demo: true));

      expect(find.byType(AppQrOverlayWidget), findsOneWidget);
      expect(find.text(TextConstants.qrEnterManually), findsOneWidget);
      expect(find.byTooltip(TextConstants.tooltipFlashlight), findsOneWidget);
      expect(find.byTooltip(TextConstants.tooltipSwitchCamera), findsOneWidget);
    });

    testWidgets('an invalid QR shows a snackbar and keeps scanning', (tester) async {
      await pumpApp(tester, const QrScanPage(demo: true));

      await tester.tap(find.widgetWithText(OutlinedButton, 'invalid'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));

      expect(find.text(TextConstants.qrInvalidSnackbar), findsOneWidget);
      expect(find.byType(AppQrOverlayWidget), findsOneWidget);
    });

    testWidgets('toggling the torch does not throw', (tester) async {
      await pumpApp(tester, const QrScanPage(demo: true));

      await tester.tap(find.byTooltip(TextConstants.tooltipFlashlight));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('scan result', () {
    testWidgets('a valid scan pops the decoded id back to the caller', (tester) async {
      final bloc = QrScanBloc()..add(const QrScanEvent.permissionResolved(CameraPermissionStatus.granted));
      String? captured = 'sentinel';
      await pumpApp(
        tester,
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                captured = await Navigator.of(context).push<String?>(
                  MaterialPageRoute<String?>(
                    builder: (_) => QrScanPage(bloc: bloc, previewBuilder: (_) => const SizedBox.expand()),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      bloc.add(QrScanEvent.detected(NoxQrEnvelope.encode('alice')));
      await tester.pumpAndSettle();

      expect(captured, 'alice');
      expect(find.byType(QrScanPage), findsNothing);
    });

    testWidgets('Enter manually returns to the caller with no value (FR-013)', (tester) async {
      final bloc = QrScanBloc()..add(const QrScanEvent.permissionResolved(CameraPermissionStatus.granted));
      String? captured = 'sentinel';
      await pumpApp(
        tester,
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                captured = await Navigator.of(context).push<String?>(
                  MaterialPageRoute<String?>(
                    builder: (_) => QrScanPage(bloc: bloc, previewBuilder: (_) => const SizedBox.expand()),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(TextConstants.qrEnterManually));
      await tester.pumpAndSettle();

      expect(find.byType(QrScanPage), findsNothing);
      expect(captured, isNull);
    });
  });

  test('the scanner controller never captures frame images (privacy, FR-018/SC-007)', () {
    final controller = QrScanPage.createController();
    expect(controller.returnImage, isFalse);
    expect(controller.formats, const [BarcodeFormat.qrCode]);
  });
}
