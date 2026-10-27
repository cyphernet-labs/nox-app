@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/qr/camera_permission_status.dart';
import 'package:nox_app/presentation/pages/qr_scan_page/bloc/qr_scan_bloc.dart';
import 'package:nox_app/presentation/pages/qr_scan_page/qr_scan_page.dart';

import '../../../utils/golden.dart';

/// Scanning state via the test seams: a bloc seeded to `scanning` + a neutral
/// camera placeholder (the live MobileScanner can't render in a golden). The
/// reticle + mask are brand-fixed (#FAFAFA / #000 @ 55%): identical in both
/// themes; only the AppBar / placeholder surfaces differ by theme.
QrScanPage _scanning() => QrScanPage(
  bloc: QrScanBloc()..add(const QrScanEvent.permissionResolved(CameraPermissionStatus.granted)),
  previewBuilder: (context) => ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
);

/// Permission-denied opaque surface (mobile: centered surface; desktop: OnboardCard).
QrScanPage _denied() => QrScanPage(
  bloc: QrScanBloc()..add(const QrScanEvent.permissionResolved(CameraPermissionStatus.permanentlyDenied)),
  previewBuilder: (_) => const SizedBox.expand(),
);

/// Camera-unavailable opaque surface (no camera, e.g. iOS simulator) — recoverable
/// in-screen state with Enter manually, NOT the generic error screen.
QrScanPage _unavailable() => QrScanPage(
  bloc: QrScanBloc()..add(const QrScanEvent.permissionResolved(CameraPermissionStatus.unavailable)),
  previewBuilder: (_) => const SizedBox.expand(),
);

void main() {
  goldenTest('qr_scan_page', _scanning);
  goldenTestDesktop('qr_scan_page', _scanning);
  goldenTest('qr_scan_page_denied', _denied);
  goldenTestDesktop('qr_scan_page_denied', _denied);
  goldenTest('qr_scan_page_unavailable', _unavailable);
  goldenTestDesktop('qr_scan_page_unavailable', _unavailable);
}
