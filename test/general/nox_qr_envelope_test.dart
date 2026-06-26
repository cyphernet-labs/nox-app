import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/nox_qr_envelope.dart';

void main() {
  group('NoxQrEnvelope.encode', () {
    test('wraps the identifier in the nox://id/ envelope, percent-encoded', () {
      expect(NoxQrEnvelope.encode('alice'), 'nox://id/alice');
    });

    test('percent-encodes URI-reserved characters so the path stays one segment', () {
      expect(NoxQrEnvelope.encode('a/b'), 'nox://id/a%2Fb');
      expect(NoxQrEnvelope.encode('a b?c#d'), 'nox://id/a%20b%3Fc%23d');
    });

    test('an empty identifier yields the unscannable bare envelope', () {
      expect(NoxQrEnvelope.encode(''), 'nox://id/');
    });
  });

  group('NoxQrEnvelope.decode round-trips encode for any non-empty id', () {
    const ids = <String>[
      'alice',
      'a/b',
      'a b?c#d',
      'NOX-7c1f9a4e2b8d40f3',
      'aGVsbG8td29ybGQ=', // base64-ish (+ / =)
      'Ключ-Москва-✓', // unicode
      r'weird:value%with#chars',
    ];
    for (final id in ids) {
      test('round-trips "$id"', () {
        expect(NoxQrEnvelope.decode(NoxQrEnvelope.encode(id)), id);
      });
    }

    test('does NOT double-decode a literal %xx in the identifier', () {
      // id contains a literal "%2F"; encode escapes the % itself; decode must
      // return the literal back, not interpret it as "/".
      const id = 'a%2Fb';
      expect(NoxQrEnvelope.decode(NoxQrEnvelope.encode(id)), id);
    });
  });

  group('NoxQrEnvelope.decode returns null for invalid / foreign payloads', () {
    test('empty or whitespace-only', () {
      expect(NoxQrEnvelope.decode(''), isNull);
      expect(NoxQrEnvelope.decode('   '), isNull);
    });

    test('foreign schemes (URL, Wi-Fi, vCard)', () {
      expect(NoxQrEnvelope.decode('https://example.com/x'), isNull);
      expect(NoxQrEnvelope.decode('WIFI:S:net;T:WPA;P:pwd;;'), isNull);
      expect(NoxQrEnvelope.decode('BEGIN:VCARD'), isNull);
    });

    test('wrong host/type', () {
      expect(NoxQrEnvelope.decode('nox://other/x'), isNull);
    });

    test('empty path (bare envelope)', () {
      expect(NoxQrEnvelope.decode('nox://id/'), isNull);
    });

    test('more than one path segment', () {
      expect(NoxQrEnvelope.decode('nox://id/a/b'), isNull);
    });

    test('encode of empty id is not decodable (US3 invalid path)', () {
      expect(NoxQrEnvelope.decode(NoxQrEnvelope.encode('')), isNull);
    });

    test('trims surrounding whitespace on the envelope', () {
      expect(NoxQrEnvelope.decode('  nox://id/alice  '), 'alice');
    });
  });
}
