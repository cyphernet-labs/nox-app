import 'package:nox_app/general/platform_utils.dart';
import 'package:nox_app/general/qr_scanner_capability.dart';

/// Whether the "pick a QR image" sign-in fallback is offered on Login (2.1). Shown only
/// where the camera scanner is ABSENT and it is a desktop file environment — i.e.
/// Windows/Linux (macOS keeps the camera path via [QrScannerCapability]). This gives the
/// two camera-less desktops a QR sign-in at parity with the scan platforms (feature P14).
///
/// Derived entirely from [QrScannerCapability]; tests exercise the Windows/Linux branch by
/// setting `QrScannerCapability.debugOverride = false` on the (desktop) test host — no seam
/// of its own is needed.
abstract final class QrImageSignInCapability {
  const QrImageSignInCapability._();

  static bool get isAvailable => PlatformUtils.isDesktop && !QrScannerCapability.isAvailable;
}
