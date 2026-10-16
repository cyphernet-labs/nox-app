import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nox_tor/secure_box.dart';
import 'package:test/test.dart';

// RustSecureBox through the module's C ABI (phase 050): the library loads
// under `dart test` like the vault does, so these run the real code.

Uint8List _hex(String text) =>
    Uint8List.fromList([for (var i = 0; i < text.length; i += 2) int.parse(text.substring(i, i + 2), radix: 16)]);

String _toHex(Uint8List bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  const box = NativeSecureBoxApi();

  test('a pair signs, and only its own signature checks', () {
    final device = box.generateKeys();
    final stranger = box.generateKeys();
    expect(device.privateKey, hasLength(32));
    expect(device.publicKey, hasLength(32));

    final challenge = box.getChallenge(device.privateKey);
    expect(challenge.publicKey, device.publicKey, reason: 'the challenge comes with the pair\'s own key');

    final signature = box.signChallenge(device.privateKey, challenge.challenge);
    expect(signature, hasLength(64));
    expect(box.checkSignature(device.publicKey, challenge.challenge, signature), isTrue);
    expect(box.checkSignature(stranger.publicKey, challenge.challenge, signature), isFalse);
    final changed = Uint8List.fromList(signature)..[0] ^= 1;
    expect(box.checkSignature(device.publicKey, challenge.challenge, changed), isFalse);
  });

  test('challenges do not repeat', () {
    final pair = box.generateKeys();
    final seen = <String>{for (var i = 0; i < 200; i++) _toHex(box.getChallenge(pair.privateKey).challenge)};
    expect(seen, hasLength(200));
  });

  test('an argument of the wrong length never reaches the module', () {
    final pair = box.generateKeys();
    expect(() => box.getChallenge(Uint8List(31)), throwsArgumentError);
    expect(() => box.signChallenge(pair.privateKey, Uint8List(33)), throwsArgumentError);
    expect(() => box.checkSignature(pair.publicKey, Uint8List(32), Uint8List(63)), throwsArgumentError);
  });

  test('the module gives the shared vectors of the implementation they name', () {
    final file = File('../../specs/050-rust-secure-box/contracts/rsb-vectors.json');
    final vectors = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final probe = vectors['probe'] as Map<String, dynamic>;
    expect(_toHex(box.getChallenge(_hex(probe['private_key'] as String)).publicKey), probe['public_key']);
    for (final row in (vectors['signatures'] as List).cast<Map<String, dynamic>>()) {
      final signature = box.signChallenge(_hex(row['private_key'] as String), _hex(row['challenge'] as String));
      expect(_toHex(signature), row['signature']);
    }
    for (final row in (vectors['checks'] as List).cast<Map<String, dynamic>>()) {
      final valid = box.checkSignature(
        _hex(row['public_key'] as String),
        _hex(row['challenge'] as String),
        _hex(row['signature'] as String),
      );
      expect(valid, row['valid']);
    }
  });
}
