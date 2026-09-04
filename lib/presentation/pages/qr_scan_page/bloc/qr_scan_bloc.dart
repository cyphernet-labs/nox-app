import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/model/qr/camera_permission_status.dart';
import 'package:nox_app/general/pairing/pairing_link.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';

part 'qr_scan_bloc.freezed.dart';
part 'qr_scan_event.dart';
part 'qr_scan_state.dart';

/// QR scan (2.2) state machine. PURE: no DI, no permission_handler / mobile_scanner.
/// The WIDGET owns the camera + permission orchestration and feeds this bloc
/// [PermissionResolved] / [Detected] events. This keeps the bloc trivially
/// unit-testable and lets the demo/gallery drive every state without touching the
/// camera or storage (SC-008). Bare substate names, like [LoginState].
class QrScanBloc extends BaseBloc<QrScanEvent, QrScanState> {
  QrScanBloc() : super(const QrScanState()) {
    on<Started>(_onStarted);
    on<PermissionResolved>(_onPermissionResolved);
    on<Detected>(_onDetected);
    on<SignalHandled>(_onSignalHandled);
  }

  void _onStarted(Started event, Emitter<QrScanState> emit) {
    emit(state.copyWith(status: QrScanStatus.initializing));
  }

  void _onPermissionResolved(PermissionResolved event, Emitter<QrScanState> emit) {
    // A late resume after a successful decode must not restart the camera on a
    // page that is already popping (single-shot guard).
    if (state.decodedId != null) return;
    emit(state.copyWith(status: _statusFor(event.status)));
  }

  void _onDetected(Detected event, Emitter<QrScanState> emit) {
    // Single-shot: ignore everything after the first accepted code.
    if (state.decodedId != null) return;
    // The QR carries a pairing link now, and the whole link is what the
    // sign-in path needs: the address, the server key and the token travel
    // together, so nothing is extracted out of it here.
    if (PairingLink.tryParse(event.raw) == null) {
      // Foreign / unreadable QR — keep scanning, surface a one-shot inline error.
      emit(state.copyWith(invalid: true));
      return;
    }
    emit(state.copyWith(decodedId: event.raw.trim()));
  }

  void _onSignalHandled(SignalHandled event, Emitter<QrScanState> emit) {
    emit(state.copyWith(decodedId: null, invalid: false));
  }

  QrScanStatus _statusFor(CameraPermissionStatus permission) => switch (permission) {
    CameraPermissionStatus.granted => QrScanStatus.scanning,
    CameraPermissionStatus.denied => QrScanStatus.permissionDenied,
    CameraPermissionStatus.permanentlyDenied => QrScanStatus.permissionDenied,
    CameraPermissionStatus.unavailable => QrScanStatus.fatal,
  };
}
