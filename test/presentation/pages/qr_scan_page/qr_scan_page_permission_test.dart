import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/qr/camera_permission_status.dart';
import 'package:nox_app/domain/repository/qr/camera_permission_service.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/pages/error_page/error_page.dart';
import 'package:nox_app/presentation/pages/qr_scan_page/bloc/qr_scan_bloc.dart';
import 'package:nox_app/presentation/pages/qr_scan_page/qr_scan_page.dart';

import '../../../utils/pump_app.dart';

/// Records Open-settings invocations; the scanner widget resolves this via the
/// global alias, so it's registered into the DI container for the tap test.
class _FakePermission implements CameraPermissionService {
  int openSettingsCalls = 0;

  @override
  Future<void> openSettings() async => openSettingsCalls++;

  @override
  Future<CameraPermissionStatus> request() async => CameraPermissionStatus.granted;

  @override
  Future<CameraPermissionStatus> status() async => CameraPermissionStatus.granted;
}

QrScanPage _seeded(CameraPermissionStatus permission) =>
    QrScanPage(bloc: QrScanBloc()..add(QrScanEvent.permissionResolved(permission)), previewBuilder: (_) => const SizedBox.expand());

void main() {
  group('permission-denied', () {
    testWidgets('shows the opaque surface with title, message and Open settings', (tester) async {
      await pumpApp(tester, _seeded(CameraPermissionStatus.permanentlyDenied));

      expect(find.text(TextConstants.qrPermissionTitle), findsOneWidget);
      expect(find.text(TextConstants.qrPermissionMessage), findsOneWidget);
      expect(find.text(TextConstants.actionOpenSettings), findsOneWidget);
    });

    testWidgets('Open settings asks the permission service to open system settings', (tester) async {
      final fake = _FakePermission();
      if (getIt.isRegistered<CameraPermissionService>()) getIt.unregister<CameraPermissionService>();
      getIt.registerSingleton<CameraPermissionService>(fake);
      addTearDown(() => getIt.reset());

      await pumpApp(tester, _seeded(CameraPermissionStatus.permanentlyDenied));
      await tester.tap(find.text(TextConstants.actionOpenSettings));
      await tester.pump();

      expect(fake.openSettingsCalls, 1);
    });
  });

  testWidgets('a foreign QR shows the invalid snackbar and keeps scanning', (tester) async {
    final bloc = QrScanBloc()..add(const QrScanEvent.permissionResolved(CameraPermissionStatus.granted));
    await pumpApp(tester, QrScanPage(bloc: bloc, previewBuilder: (_) => const SizedBox.expand()));

    bloc.add(const QrScanEvent.detected('https://example.com'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(TextConstants.qrInvalidSnackbar), findsOneWidget);
  });

  testWidgets('camera unavailable routes to the universal error screen (3.1)', (tester) async {
    // Drive the transition AFTER the page subscribes, so the navigation listener
    // observes scanning → fatal (a seeded-fatal state would never fire the listener).
    final bloc = QrScanBloc()..add(const QrScanEvent.permissionResolved(CameraPermissionStatus.granted));
    await pumpApp(tester, QrScanPage(bloc: bloc, previewBuilder: (_) => const SizedBox.expand()));

    bloc.add(const QrScanEvent.permissionResolved(CameraPermissionStatus.unavailable));
    await tester.pumpAndSettle();

    expect(find.byType(AppErrorPage), findsOneWidget);
  });

  blocTest<QrScanBloc, QrScanState>(
    'auto-resume: granting after a denial moves back to scanning (FR-006)',
    build: QrScanBloc.new,
    seed: () => const QrScanState(status: QrScanStatus.permissionDenied),
    act: (bloc) => bloc.add(const QrScanEvent.permissionResolved(CameraPermissionStatus.granted)),
    expect: () => const [QrScanState(status: QrScanStatus.scanning)],
  );
}
