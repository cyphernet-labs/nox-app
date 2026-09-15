import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/pairing/server_pin.dart';

/// The fixtures are generated in Go and described in their own README: nothing
/// on the Dart side can mint an X.509 certificate, and adding a package to do
/// it for one test is not on the table.
const String _dir = 'test/general/pairing/fixtures';

List<int> _der(String name) => File('$_dir/$name.der').readAsBytesSync();

String get _fingerprint => File('$_dir/fingerprint.txt').readAsStringSync().trim();

void main() {
  test('the fingerprint file really is the hash of the certificate it belongs to', () {
    // Guards the whole file: every case below is meaningless if the fixture's
    // fingerprint and its certificate were never the same key.
    expect(ServerPin.matches(_der('valid'), _fingerprint), isTrue);
  });

  group('the key decides, and only the key', () {
    test('somebody else key is refused', () {
      expect(ServerPin.matches(_der('stranger'), _fingerprint), isFalse);
    });

    test('a NEW certificate on the SAME key is accepted, because a restart issues one', () {
      // The server rebuilds its certificate on every start. If this were
      // refused, restarting the machine would lock out every device on it.
      expect(_der('reissued'), isNot(_der('valid')), reason: 'the fixture must actually be a different certificate');
      expect(ServerPin.matches(_der('reissued'), _fingerprint), isTrue);
    });

    test('an expired certificate on the right key is ACCEPTED', () {
      // Asserted positively on purpose. An implementation that refuses on
      // dates passes every negative test here and then breaks on the first
      // home server whose owner had not touched it for years.
      expect(ServerPin.matches(_der('expired'), _fingerprint), isTrue);
    });

    test('a certificate naming somebody else on the right key is ACCEPTED', () {
      // It says mail.example.com and 203.0.113.7. A home server has no name
      // and its address changes; refusing on either is a refusal nobody can
      // explain or repair.
      expect(ServerPin.matches(_der('wrong_name'), _fingerprint), isTrue);
    });

    test('a certificate from an authority nothing trusts on the right key is ACCEPTED', () {
      // Trust comes from the link a person carried here, not from an issuer.
      expect(ServerPin.matches(_der('unknown_issuer'), _fingerprint), isTrue);
    });
  });

  group('malformed input is an answer, never an exception', () {
    // The check runs inside the TLS stack certificate callback, where a throw
    // has nowhere useful to go.
    test('a truncated certificate is refused, not hashed to whatever follows the header', () {
      expect(ServerPin.matches(_der('truncated'), _fingerprint), isFalse);
    });

    test('a certificate with no P-256 key in it is refused', () {
      // An Ed25519 certificate: not a hypothetical, it is what this server
      // issued before feature 036.
      expect(ServerPin.matches(_der('headerless'), _fingerprint), isFalse);
    });

    test('empty, tiny and garbage input is refused', () {
      expect(ServerPin.matches(<int>[], _fingerprint), isFalse);
      expect(ServerPin.matches(List<int>.filled(10, 0x30), _fingerprint), isFalse);
      expect(ServerPin.matches(List<int>.filled(4096, 0xFF), _fingerprint), isFalse);
    });

    test('a certificate that is nothing but the header is refused', () {
      // The prefix with no key behind it at all - the shortest way to reach
      // the "found it" branch with nothing to hash.
      final header = _der('valid').sublist(0, 200);
      final start = _indexOfHeader(header);
      expect(start, greaterThanOrEqualTo(0), reason: 'the fixture must contain the header this test trims to');
      expect(ServerPin.matches(header.sublist(0, start + 26), _fingerprint), isFalse);
    });
  });

  group('having nothing to compare against is a refusal', () {
    // FR-009. "No fingerprint" must never mean "accept anything": an install
    // with nothing to check is exactly the install that must not connect.
    test('a null fingerprint refuses a certificate that is otherwise right', () {
      expect(ServerPin.matches(_der('valid'), null), isFalse);
    });

    test('an empty fingerprint refuses it too', () {
      expect(ServerPin.matches(_der('valid'), ''), isFalse);
    });

    test('a null certificate is refused', () {
      expect(ServerPin.matches(null, _fingerprint), isFalse);
    });

    test('a fingerprint of the right shape but the wrong value is refused', () {
      // Not a malformed input - a well-formed answer to the wrong question.
      final other = base64.encode(List<int>.filled(32, 7));
      expect(ServerPin.matches(_der('valid'), other), isFalse);
    });
  });
}

const List<int> _p256Header = <int>[
  0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, //
  0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, //
  0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, //
  0x42, 0x00,
];

int _indexOfHeader(List<int> der) {
  for (var i = 0; i + _p256Header.length <= der.length; i++) {
    var hit = true;
    for (var j = 0; j < _p256Header.length; j++) {
      if (der[i + j] != _p256Header[j]) {
        hit = false;
        break;
      }
    }
    if (hit) return i;
  }
  return -1;
}
