import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/pairing/device_keys.dart';

void main() {
  // RFC 8032's seed 00..1f and the public key every Ed25519 implementation
  // derives from it - the native module and the server among them. A swapped
  // library or a base64-vs-raw slip is caught here rather than by a device
  // the server no longer recognises.
  const seed = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=';
  const publicKey = 'A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=';

  test('the public key derived from a seed matches the pinned vector', () async {
    expect(await DeviceKeys.publicKey(seed), publicKey);
  });

  test('a generated seed is 32 bytes and differs every time', () async {
    final first = await DeviceKeys.generateSeed();
    final second = await DeviceKeys.generateSeed();
    expect(base64.decode(first).length, 32);
    expect(first, isNot(second));
  });

  test('the same seed always yields the same public key', () async {
    final seed = await DeviceKeys.generateSeed();
    expect(await DeviceKeys.publicKey(seed), await DeviceKeys.publicKey(seed));
  });
}
