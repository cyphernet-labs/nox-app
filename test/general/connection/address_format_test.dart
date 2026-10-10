import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/connection/address_format.dart';

/// The format checks of the addresses a person types (phase 045, FR-004 on
/// the server side, FR-013 and FR-014 here): format only - who answers is
/// decided by the server key.
void main() {
  /// RFC 8032 test 1's public key, and the onion address the server and the
  /// Tor module both derive from it (`nox_tor_test.dart`).
  final rfcKey = Uint8List.fromList([
    0xd7, 0x5a, 0x98, 0x01, 0x82, 0xb1, 0x0a, 0xb7, 0xd5, 0x4b, 0xfe, 0xd3, 0xc9, 0x64, 0x07, 0x3a, //
    0x0e, 0xe1, 0x72, 0xf3, 0xda, 0xa6, 0x23, 0x25, 0xaf, 0x02, 0x1a, 0x68, 0xf7, 0x07, 0x51, 0x1a,
  ]);
  const rfcOnion = '25njqamcweflpvkl73j4szahhihoc4xt3ktcgjnpaingr5yhkenl5sid.onion';

  /// The module's arithmetic for the one key it is asked about here.
  String? derive(Uint8List key) {
    for (var i = 0; i < key.length; i++) {
      if (key[i] != rfcKey[i]) return 'someotheraddresssomeotheraddresssomeotheraddresssomeoth.onion';
    }
    return rfcOnion;
  }

  group('a server address', () {
    for (final good in [
      '192.168.1.20:8443',
      '10.0.0.1:1',
      'nox.example.org:8443',
      'NOX.Example.ORG:443',
      'localhost:65535',
      'my-server.lan:8080',
      '[fd12:3456::20]:8443',
      '[::1]:9000',
      '  192.168.1.20:8443  ',
    ]) {
      test('"$good" is one', () => expect(AddressFormat.isServerAddress(good), isTrue));
    }

    for (final bad in [
      '',
      'nox.example.org',
      '192.168.1.20',
      '192.168.1.20:',
      ':8443',
      '192.168.1.20:0',
      '192.168.1.20:65536',
      '192.168.1.20:+80',
      'fd12:3456::20:8443',
      '[fd12:3456::20:8443',
      '[192.168.1.20]:8443',
      'https://nox.example.org:8443',
      'nox.example.org:8443/ws',
      'user@nox.example.org:8443',
      'nox example.org:8443',
      '-nox.example.org:8443',
      'nox-.example.org:8443',
      'nox..example.org:8443',
      '${'a' * 64}.org:8443',
      '$rfcOnion:443',
    ]) {
      test('"$bad" is not one', () => expect(AddressFormat.isServerAddress(bad), isFalse));
    }

    test('a name longer than DNS allows is not one', () {
      final long = List<String>.filled(5, 'a' * 60).join('.');
      expect(long.length, greaterThan(253));
      expect(AddressFormat.isServerAddress('$long:1'), isFalse);
    });
  });

  group('an onion address', () {
    test('a v3 address reads as stored, with the service port', () {
      expect(AddressFormat.normalizeOnion(rfcOnion, derive: derive), '$rfcOnion:443');
    });

    test('case, spaces and an explicit :443 make no difference', () {
      expect(AddressFormat.normalizeOnion('  ${rfcOnion.toUpperCase()}:443 ', derive: derive), '$rfcOnion:443');
    });

    test('a checksum that does not hold is refused - a typo the module would refuse anyway', () {
      // One character of the key changed: still base32, still version 3.
      final typo = '25njqb${rfcOnion.substring(6)}';
      expect(AddressFormat.normalizeOnion(typo, derive: derive), isNull);
    });

    test('without the module the format is checked, and the checksum left to the module that dials', () {
      final typo = '25njqb${rfcOnion.substring(6)}';
      expect(AddressFormat.normalizeOnion(typo), '$typo:443');
      expect(AddressFormat.normalizeOnion(rfcOnion, derive: (_) => null), '$rfcOnion:443');
    });

    for (final bad in [
      '',
      'example.onion',
      '${'a' * 56}.onion', // version byte 0, not 3
      '25njqamcweflpvkl73j4szahhihoc4xt3ktcgjnpaingr5yhkenl5sie.onion', // version byte 4
      '${rfcOnion.substring(0, 55)}.onion',
      '${rfcOnion}x',
      '$rfcOnion:8443',
      'http://$rfcOnion',
      '25njqamcweflpvkl73j4szahhihoc4xt3ktcgjnpaingr5yhkenl5si1.onion',
      'nox.example.org:8443',
    ]) {
      test('"$bad" is not one', () => expect(AddressFormat.normalizeOnion(bad, derive: derive), isNull));
    }

    test('the field shows the host alone', () {
      expect(AddressFormat.onionHostOf('$rfcOnion:443'), rfcOnion);
      expect(AddressFormat.onionHostOf(rfcOnion), rfcOnion);
    });
  });
}
