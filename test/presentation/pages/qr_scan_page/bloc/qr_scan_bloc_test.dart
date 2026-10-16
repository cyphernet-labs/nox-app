import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/qr/camera_permission_status.dart';
import 'package:nox_app/general/pairing/pairing_link.dart';
import 'package:nox_app/presentation/pages/qr_scan_page/bloc/qr_scan_bloc.dart';

/// A version-4 link: newer than this build reads.
const String _newer = 'nox://pair/BKCapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODw';

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
      'a readable pairing link sets decodedId to the WHOLE link',
      build: QrScanBloc.new,
      seed: () => const QrScanState(status: QrScanStatus.scanning),
      act: (bloc) => bloc.add(QrScanEvent.detected(PairingLink.demo)),
      expect: () => const [QrScanState(status: QrScanStatus.scanning, decodedId: PairingLink.demo)],
    );

    blocTest<QrScanBloc, QrScanState>(
      'a link from a newer server is handed on too: the sign-in screen says to update the app (FR-017)',
      build: QrScanBloc.new,
      seed: () => const QrScanState(status: QrScanStatus.scanning),
      act: (bloc) => bloc.add(const QrScanEvent.detected(_newer)),
      expect: () => const [QrScanState(status: QrScanStatus.scanning, decodedId: _newer)],
    );

    blocTest<QrScanBloc, QrScanState>(
      'a link of the format before version 3 is not a pairing link any more',
      build: QrScanBloc.new,
      seed: () => const QrScanState(status: QrScanStatus.scanning),
      act: (bloc) => bloc.add(
        const QrScanEvent.detected('https://nox.app/p/#AQF_AAABH5CjZmMytIk_2XvPJ-jonqlQtYsZD3SB33P1foxqnrVbFo-VEf6WohQoqA1_na5iVUo'),
      ),
      expect: () => const [QrScanState(status: QrScanStatus.scanning, invalid: true)],
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
      seed: () => const QrScanState(status: QrScanStatus.scanning, decodedId: PairingLink.demo),
      act: (bloc) => bloc.add(QrScanEvent.detected(PairingLink.demo)),
      expect: () => const <QrScanState>[],
    );

    blocTest<QrScanBloc, QrScanState>(
      'a late permission result after a decode is ignored (no camera restart)',
      build: QrScanBloc.new,
      seed: () => const QrScanState(status: QrScanStatus.scanning, decodedId: PairingLink.demo),
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
