import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/service/tor/tor_capability.dart';
import 'package:nox_tor/nox_tor.dart';

/// Tor is built into the app on all five platforms since phase 045 - Linux
/// among them (FR-010): whether it is offered follows the native library
/// alone, never the platform's name.
void main() {
  tearDown(() => TorCapability.debugOverride = null);

  test('Tor is offered wherever the native library loads, on every platform', () {
    expect(TorCapability.isAvailable, NoxTor.isSupported);
  });

  test('a test can still take either branch', () {
    TorCapability.debugOverride = false;
    expect(TorCapability.isAvailable, isFalse);
    TorCapability.debugOverride = true;
    expect(TorCapability.isAvailable, isTrue);
  });
}
