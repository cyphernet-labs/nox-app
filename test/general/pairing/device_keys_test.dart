import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/pairing/device_keys.dart';

void main() {
  // The vector is the one pinned in contract §3, produced by signing in Dart
  // and verifying in Go before either side was written. It is here so that a
  // swapped library, a changed prefix or a base64-vs-raw slip is caught by a
  // test rather than by a device that silently stops connecting.
  const seed = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=';
  const publicKey = 'A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=';

  test('the public key derived from a seed matches the pinned vector', () async {
    expect(await DeviceKeys.publicKey(seed), publicKey);
  });

  test('signing the challenge matches the pinned vector', () async {
    // "probe" is what the vector's message is, minus the prefix the signer adds.
    final challenge = base64.encode(utf8.encode('probe'));
    final signature = await DeviceKeys.signChallenge(seed: seed, challenge: challenge);
    expect(signature, 'puHNSjLy6sqx5MEgiAuZiz6Zuyjohrz0EIEjkdQ9iazgyIEeUvGbK+UAIhHjpscFPCMBN7rpbfeoXr1UZXQZBQ==');
  });

  test('a different challenge produces a different signature', () async {
    final one = await DeviceKeys.signChallenge(seed: seed, challenge: base64.encode(utf8.encode('a')));
    final two = await DeviceKeys.signChallenge(seed: seed, challenge: base64.encode(utf8.encode('b')));
    expect(one, isNot(two));
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
