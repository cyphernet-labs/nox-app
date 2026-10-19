import 'dart:convert';
import 'dart:typed_data';

import 'package:nox_tor/vault.dart';
import 'package:test/test.dart';

// The vault against the library the hook built for the host. Its key is the
// module's, one for the whole process: the tests of this file run one after
// another, each from the key it sets, and no other file of the package
// touches the vault.
void main() {
  final key = Uint8List.fromList(List<int>.generate(32, (i) => 0x40 + i));
  final otherKey = Uint8List.fromList(List<int>.generate(32, (i) => 0x80 + i));
  final text = bytes('a message of the local database');
  // A file's name as the app gives it: the hex of a random 16-byte id kept in
  // the file's header.
  const name = '8f14e45fceea167a5a36dedd4bea2543';

  setUp(() => NoxVault.setKey(key));
  tearDown(NoxVault.clear);

  group('a record', () {
    test('goes round, between its nonce and its tag', () {
      final sealed = NoxVault.seal(text);
      expect(sealed, hasLength(text.length + NoxVault.recordOverhead));
      expect(NoxVault.open(sealed), text);
      expect(NoxVault.open(NoxVault.seal(Uint8List(0))), isEmpty);
    });

    test('sealed twice is two different results, both opening', () {
      final first = NoxVault.seal(text);
      final second = NoxVault.seal(text);
      expect(first.sublist(0, 12), isNot(second.sublist(0, 12)), reason: 'a fresh nonce each time');
      expect(first, isNot(second));
      expect(NoxVault.open(second), text);
    });

    test('under another key is forged', () {
      final sealed = NoxVault.seal(text);
      NoxVault.setKey(otherKey);
      expect(() => NoxVault.open(sealed), failsWith(VaultCode.forged));
    });

    test('with a bit flipped anywhere, or cut short, is forged', () {
      final sealed = NoxVault.seal(text);
      for (var at = 0; at < sealed.length; at++) {
        expect(() => NoxVault.open(flipped(sealed, at)), failsWith(VaultCode.forged), reason: 'byte $at');
      }
      for (final length in [0, 1, 27, sealed.length - 1]) {
        expect(() => NoxVault.open(sealed.sublist(0, length)), failsWith(VaultCode.forged), reason: '$length bytes');
      }
    });
  });

  group('a chunk', () {
    test('goes round, its tag after it', () {
      final full = Uint8List(64 * 1024)..fillRange(0, 64 * 1024, 0xA5);
      for (final (index, last, plain) in [(0, false, full), (1, false, full), (2, true, text), (0, true, Uint8List(0))]) {
        final sealed = NoxVault.sealChunk(name, index, last: last, data: plain);
        expect(sealed, hasLength(plain.length + NoxVault.chunkOverhead));
        expect(
          NoxVault.openChunk(name, index, last: last, data: sealed),
          plain,
          reason: 'chunk $index',
        );
      }
    });

    test('opens only as what it was sealed as: the last one or not', () {
      final inner = NoxVault.sealChunk(name, 4, last: false, data: text);
      final end = NoxVault.sealChunk(name, 4, last: true, data: text);
      // A file cut at a chunk boundary: its new end was not sealed as the last.
      expect(() => NoxVault.openChunk(name, 4, last: true, data: inner), failsWith(VaultCode.forged));
      expect(() => NoxVault.openChunk(name, 4, last: false, data: end), failsWith(VaultCode.forged));
    });

    test('opens only at its own index, and only in its own file', () {
      final sealed = NoxVault.sealChunk(name, 7, last: false, data: text);
      for (final index in [0, 6, 8, 7 + (1 << 32)]) {
        expect(() => NoxVault.openChunk(name, index, last: false, data: sealed), failsWith(VaultCode.forged), reason: '$index');
      }
      // Byte for byte: a digit off, the same id in capitals, half of it.
      for (final other in ['8f14e45fceea167a5a36dedd4bea2544', '8F14E45FCEEA167A5A36DEDD4BEA2543', '8f14e45fceea167a']) {
        expect(() => NoxVault.openChunk(other, 7, last: false, data: sealed), failsWith(VaultCode.forged), reason: other);
      }
    });

    test('under another key, or with a bit flipped, is forged', () {
      final sealed = NoxVault.sealChunk(name, 0, last: true, data: text);
      for (var at = 0; at < sealed.length; at++) {
        expect(() => NoxVault.openChunk(name, 0, last: true, data: flipped(sealed, at)), failsWith(VaultCode.forged));
      }
      NoxVault.setKey(otherKey);
      expect(() => NoxVault.openChunk(name, 0, last: true, data: sealed), failsWith(VaultCode.forged));
    });
  });

  group('the key', () {
    test('not set: nothing seals or opens', () {
      NoxVault.clear();
      expect(() => NoxVault.seal(text), failsWith(VaultCode.noKey));
      expect(() => NoxVault.open(Uint8List(40)), failsWith(VaultCode.noKey));
      expect(() => NoxVault.sealChunk(name, 0, last: true, data: text), failsWith(VaultCode.noKey));
      expect(() => NoxVault.openChunk(name, 0, last: true, data: Uint8List(40)), failsWith(VaultCode.noKey));
    });

    test('cleared, it is gone; set again, the data opens again', () {
      final record = NoxVault.seal(text);
      final chunk = NoxVault.sealChunk(name, 0, last: true, data: text);
      NoxVault.clear();
      expect(() => NoxVault.open(record), failsWith(VaultCode.noKey));
      NoxVault.clear();
      NoxVault.setKey(key);
      expect(NoxVault.open(record), text);
      expect(NoxVault.openChunk(name, 0, last: true, data: chunk), text);
    });

    test('of the wrong length or of all zeros is refused, and the key before stays', () {
      final sealed = NoxVault.seal(text);
      for (final bad in [Uint8List(0), Uint8List(31), Uint8List(33), Uint8List(32)]) {
        expect(() => NoxVault.setKey(bad), failsWith(VaultCode.invalidArgument), reason: '${bad.length} bytes');
      }
      expect(NoxVault.open(sealed), text);
    });

    test("is copied: the caller's bytes stay as they were", () {
      final mine = Uint8List.fromList(key);
      NoxVault.setKey(mine);
      expect(mine, key);
    });
  });

  test('an empty name, a NUL in a name and a negative index are refused before the module', () {
    for (final call in [
      () => NoxVault.sealChunk('', 0, last: true, data: text),
      () => NoxVault.sealChunk('a\u0000b', 0, last: true, data: text),
      () => NoxVault.openChunk('a\u0000b', 0, last: true, data: Uint8List(16)),
      () => NoxVault.sealChunk(name, -1, last: true, data: text),
      () => NoxVault.openChunk(name, -1, last: true, data: Uint8List(16)),
    ]) {
      expect(call, failsWith(VaultCode.invalidArgument));
    }
  });

  test('an unknown return of the module is internal', () {
    expect(VaultCode.of(-4), VaultCode.forged);
    expect(VaultCode.of(-11), VaultCode.internal);
    expect(VaultCode.of(-12), VaultCode.internal);
    expect('${const VaultException(VaultCode.noKey)}', 'VaultException(noKey)');
  });

  // Sealed by Node's crypto (OpenSSL) and Go's golang.org/x/crypto, which
  // agree byte for byte: the format as the contract writes it, reached through
  // this binding - the record under the key of records drawn on setKey, and a
  // name that is not ASCII included.
  test('what another implementation sealed opens here, and is what this one seals', () {
    NoxVault.setKey(Uint8List.fromList(List<int>.generate(32, (i) => i + 1)));
    expect(
      NoxVault.open(hex('a0a1a2a3a4a5a6a7a8a9aaab935b28fd288e079160bddccd87da69e00fceeb6b49dab2630af368d29490ba7c')),
      bytes('NOX vault record'),
    );
    const id = '00112233445566778899aabbccddeeff';
    for (final (vectorName, index, last, plain, sealed) in [
      (id, 0, false, 'chunk zero', 'cc5026cb42ab1da95c166806af9de201c00f05c68e815b4bd74b'),
      (id, 1, true, 'the last chunk', '7267288bd65d22501de660d1df4db9a0db9bcb379d8bb02b91ebaf5d00eb'),
      (id, 0x0102030405060708, true, '', 'fc2c95c8a28b0da6f24403ce154b6db7'),
      ('фото ✓', 0, true, 'a name that is not ASCII', '5f575531af2402112665172acab965a63306269e9165758877ce0febaa89ba0035df9eba58abcd43'),
    ]) {
      expect(
        NoxVault.openChunk(vectorName, index, last: last, data: hex(sealed)),
        bytes(plain),
        reason: '$vectorName $index',
      );
      expect(
        NoxVault.sealChunk(vectorName, index, last: last, data: bytes(plain)),
        hex(sealed),
        reason: '$vectorName $index',
      );
    }
  });
}

Matcher failsWith(VaultCode code) => throwsA(isA<VaultException>().having((e) => e.code, 'code', code));

Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

Uint8List hex(String text) => Uint8List.fromList([for (var i = 0; i < text.length; i += 2) int.parse(text.substring(i, i + 2), radix: 16)]);

Uint8List flipped(Uint8List sealed, int at) => Uint8List.fromList(sealed)..[at] ^= 0x01;
