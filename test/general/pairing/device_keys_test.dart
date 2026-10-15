import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/pairing/device_keys.dart';

void main() {
  // The probe of the stub's shared vectors (specs/050-rust-secure-box/
  // contracts/rsb-vectors.json): 32 bytes of 0x01 and the public key
  // RustSecureBox gives for it - the app's module and the server's WebAssembly
  // copy alike. A swapped library or a base64-vs-raw slip is caught here
  // rather than by a device the server no longer recognises.
  final probe = base64.encode(List<int>.filled(32, 1));
  final probePublic = base64.encode([
    for (var i = 0; i < 64; i += 2)
      int.parse('92254a2a0d909e16f153fa8996ee70415de255968b918cf4aec36a2136da9e84'.substring(i, i + 2), radix: 16),
  ]);

  test('the public key of a private one is RustSecureBox\'s, as the vectors pin it', () {
    expect(DeviceKeys.publicKeyOf(probe), probePublic);
  });

  test('a generated pair is two 32-byte keys, new every time, and one pair', () {
    final first = DeviceKeys.generate();
    final second = DeviceKeys.generate();
    expect(base64.decode(first.privateKey), hasLength(32));
    expect(base64.decode(first.publicKey), hasLength(32));
    expect(first.privateKey, isNot(second.privateKey));
    expect(DeviceKeys.publicKeyOf(first.privateKey), first.publicKey);
  });

  test('the same private key always yields the same public key', () {
    final pair = DeviceKeys.generate();
    expect(DeviceKeys.publicKeyOf(pair.privateKey), DeviceKeys.publicKeyOf(pair.privateKey));
  });
}
