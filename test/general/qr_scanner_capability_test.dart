import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/qr_scanner_capability.dart';

void main() {
  tearDown(() => QrScannerCapability.debugOverride = null);

  test('debugOverride=true forces the scanner available (button shown, 2.2 reachable)', () {
    QrScannerCapability.debugOverride = true;
    expect(QrScannerCapability.isAvailable, isTrue);
  });

  test('debugOverride=false forces the scanner unavailable (Windows/Linux case)', () {
    QrScannerCapability.debugOverride = false;
    expect(QrScannerCapability.isAvailable, isFalse);
  });

  test('without an override resolves from the platform (host is macOS -> available)', () {
    // The local test/golden host is macOS, a scanner platform.
    expect(QrScannerCapability.isAvailable, isTrue);
  });
}
