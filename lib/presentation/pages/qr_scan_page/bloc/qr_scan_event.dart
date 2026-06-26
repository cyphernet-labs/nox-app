part of 'qr_scan_bloc.dart';

@freezed
sealed class QrScanEvent with _$QrScanEvent {
  /// Screen opened → `initializing` (the widget then orchestrates permission).
  const factory QrScanEvent.started() = Started;

  /// Permission outcome reported by the widget (iOS/Android via permission_handler;
  /// macOS via the controller). Lifecycle resume re-reports it too (FR-006).
  const factory QrScanEvent.permissionResolved(CameraPermissionStatus status) = PermissionResolved;

  /// Raw QR value from the controller's onDetect / a demo control.
  const factory QrScanEvent.detected(String raw) = Detected;

  /// The page consumed `decodedId` / `invalid` → clear the one-shot signals.
  const factory QrScanEvent.signalHandled() = SignalHandled;
}
