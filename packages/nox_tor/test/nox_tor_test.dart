import 'dart:typed_data';

import 'package:nox_tor/nox_tor.dart';
import 'package:test/test.dart';

// These load the real library the hook built for the host - on every
// platform since phase 044. They touch no network: the client is never
// started.
void main() {
  test('the library is there and names its Arti', () {
    expect(NoxTor.isSupported, isTrue);
    expect(NoxTor.version, 'arti-client 0.47.0');
  });

  test('the onion address of RFC 8032 test 1 is the one the server pins', () {
    final pub = Uint8List.fromList([
      0xd7, 0x5a, 0x98, 0x01, 0x82, 0xb1, 0x0a, 0xb7, 0xd5, 0x4b, 0xfe, 0xd3, 0xc9, 0x64, 0x07, 0x3a, //
      0x0e, 0xe1, 0x72, 0xf3, 0xda, 0xa6, 0x23, 0x25, 0xaf, 0x02, 0x1a, 0x68, 0xf7, 0x07, 0x51, 0x1a,
    ]);
    expect(NoxTor.onionFromPublicKey(pub), '25njqamcweflpvkl73j4szahhihoc4xt3ktcgjnpaingr5yhkenl5sid.onion');
  });

  test('a stopped client reports stopped, and a target needs a started one', () {
    expect(NoxTor.status().state, NoxTorState.stopped);
    expect(
      () => NoxTor.setTarget(
        onionHost: '25njqamcweflpvkl73j4szahhihoc4xt3ktcgjnpaingr5yhkenl5sid.onion',
        port: 443,
        clientKey: Uint8List(32),
      ),
      throwsA(isA<NoxTorException>().having((e) => e.code, 'code', -8)),
    );
  });

  test('wrong lengths are refused before they reach the library', () {
    expect(() => NoxTor.onionFromPublicKey(Uint8List(31)), throwsArgumentError);
    expect(() => NoxTor.setTarget(onionHost: 'x.onion', port: 443, clientKey: Uint8List(16)), throwsArgumentError);
  });
}
