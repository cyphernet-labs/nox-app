import 'package:flutter/foundation.dart';
import 'package:nox_app/general/platform_utils.dart';

/// Single source of truth for whether the camera QR scanner exists on this
/// platform (FR-016/FR-017). Camera scan is supported only on iOS/Android/macOS
/// (`mobile_scanner`); Windows/Linux have no scanner, so the `Scan QR` button on
/// Login (2.1) is hidden AND the scan screen (2.2) is unreachable — one predicate
/// governs both.
///
/// `PlatformUtils` is built on `dart:io Platform`, which is NOT overridable via
/// `debugDefaultTargetPlatformOverride`; on the golden/test host (macOS) it always
/// reports macOS. [debugOverride] is the only way to exercise the Windows/Linux
/// hidden-button case in a test. Tests MUST reset it in tearDown.
abstract final class QrScannerCapability {
  const QrScannerCapability._();

  @visibleForTesting
  static bool? debugOverride;

  static bool get isAvailable => debugOverride ?? (PlatformUtils.isMobile || PlatformUtils.isMacOS);
}
