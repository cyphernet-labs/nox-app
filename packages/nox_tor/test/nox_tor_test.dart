import 'dart:ffi';
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

  test('a stopped client reports stopped, with nothing gone wrong', () {
    final status = NoxTor.status();
    expect(status.state, NoxTorState.stopped);
    expect(status.error, NoxTorError.none);
  });

  test('wrong lengths are refused before they reach the library', () {
    expect(() => NoxTor.onionFromPublicKey(Uint8List(31)), throwsArgumentError);
  });

  test('the onion access-key functions are gone from the library (phase 045)', () {
    // Looked up by symbol: a binding to a function the library no longer
    // exports would throw at its first call, so the test asks the library
    // itself rather than the Dart wrapper.
    final library = DynamicLibrary.process();
    // Where the loader keeps the library out of the process namespace there
    // is nothing to look in, and an absent symbol would prove nothing.
    if (!library.providesSymbol('nox_tor_version')) {
      markTestSkipped('the library is not in the process namespace here');
      return;
    }
    for (final symbol in ['nox_tor_set_target', 'nox_tor_clear_target']) {
      expect(library.providesSymbol(symbol), isFalse, reason: symbol);
    }
  });
}
