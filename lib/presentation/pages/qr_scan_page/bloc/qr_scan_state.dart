part of 'qr_scan_bloc.dart';

/// Persistent scanner phase. `initializing` = checking/requesting permission;
/// `scanning` = camera active; `permissionDenied` = opaque surface + Open settings;
/// `fatal` = camera unavailable → routed to the universal error screen (3.1).
enum QrScanStatus { initializing, scanning, permissionDenied, fatal }

@freezed
abstract class QrScanState with _$QrScanState {
  const QrScanState._();

  const factory QrScanState({
    @Default(QrScanStatus.initializing) QrScanStatus status,
    // One-shot: a valid envelope was decoded → the page pops it into Login (2.1).
    String? decodedId,
    // One-shot: a foreign/empty QR → inline snackbar; scanning continues.
    @Default(false) bool invalid,
  }) = _QrScanState;
}
