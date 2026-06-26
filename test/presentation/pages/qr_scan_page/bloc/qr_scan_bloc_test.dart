import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/qr/camera_permission_status.dart';
import 'package:nox_app/general/nox_qr_envelope.dart';
import 'package:nox_app/presentation/pages/qr_scan_page/bloc/qr_scan_bloc.dart';

void main() {
  group('QrScanBloc permission mapping', () {
    blocTest<QrScanBloc, QrScanState>(
      'granted → scanning',
      build: QrScanBloc.new,
      act: (bloc) => bloc.add(const QrScanEvent.permissionResolved(CameraPermissionStatus.granted)),
      expect: () => const [QrScanState(status: QrScanStatus.scanning)],
    );

    blocTest<QrScanBloc, QrScanState>(
      'denied → permissionDenied',
      build: QrScanBloc.new,
      act: (bloc) => bloc.add(const QrScanEvent.permissionResolved(CameraPermissionStatus.denied)),
      expect: () => const [QrScanState(status: QrScanStatus.permissionDenied)],
    );

    blocTest<QrScanBloc, QrScanState>(
      'permanentlyDenied → permissionDenied',
      build: QrScanBloc.new,
      act: (bloc) => bloc.add(const QrScanEvent.permissionResolved(CameraPermissionStatus.permanentlyDenied)),
      expect: () => const [QrScanState(status: QrScanStatus.permissionDenied)],
    );

    blocTest<QrScanBloc, QrScanState>(
      'unavailable → fatal',
      build: QrScanBloc.new,
      act: (bloc) => bloc.add(const QrScanEvent.permissionResolved(CameraPermissionStatus.unavailable)),
      expect: () => const [QrScanState(status: QrScanStatus.fatal)],
    );
  });

  group('QrScanBloc detection', () {
    blocTest<QrScanBloc, QrScanState>(
      'a valid nox://id/ envelope sets decodedId',
      build: QrScanBloc.new,
      seed: () => const QrScanState(status: QrScanStatus.scanning),
      act: (bloc) => bloc.add(QrScanEvent.detected(NoxQrEnvelope.encode('alice'))),
      expect: () => const [QrScanState(status: QrScanStatus.scanning, decodedId: 'alice')],
    );

    blocTest<QrScanBloc, QrScanState>(
      'a foreign QR flags invalid and keeps scanning',
      build: QrScanBloc.new,
      seed: () => const QrScanState(status: QrScanStatus.scanning),
      act: (bloc) => bloc.add(const QrScanEvent.detected('https://example.com')),
      expect: () => const [QrScanState(status: QrScanStatus.scanning, invalid: true)],
    );

    blocTest<QrScanBloc, QrScanState>(
      'single-shot: a second detect after a decode is ignored',
      build: QrScanBloc.new,
      seed: () => const QrScanState(status: QrScanStatus.scanning, decodedId: 'alice'),
      act: (bloc) => bloc.add(QrScanEvent.detected(NoxQrEnvelope.encode('bob'))),
      expect: () => const <QrScanState>[],
    );

    blocTest<QrScanBloc, QrScanState>(
      'a late permission result after a decode is ignored (no camera restart)',
      build: QrScanBloc.new,
      seed: () => const QrScanState(status: QrScanStatus.scanning, decodedId: 'alice'),
      act: (bloc) => bloc.add(const QrScanEvent.permissionResolved(CameraPermissionStatus.granted)),
      expect: () => const <QrScanState>[],
    );

    blocTest<QrScanBloc, QrScanState>(
      'SignalHandled clears the one-shot signals',
      build: QrScanBloc.new,
      seed: () => const QrScanState(status: QrScanStatus.scanning, invalid: true),
      act: (bloc) => bloc.add(const QrScanEvent.signalHandled()),
      expect: () => const [QrScanState(status: QrScanStatus.scanning)],
    );
  });
}
