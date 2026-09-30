import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/pairing/pairing_link.dart';

void main() {
  // Produced by the Go server, not by this parser: a link the two sides agree
  // on is the only kind worth testing. Captured from a live noxd bound to
  // 127.0.0.1:8080 on a fresh database.
  const fromServer = 'https://nox.app/p/#AQF_AAABH5CjZmMytIk_2XvPJ-jonqlQtYsZD3SB33P1foxqnrVbFo-VEf6WohQoqA1_na5iVUo';

  test('reads a link the server actually produced', () {
    final link = PairingLink.parse(fromServer);
    expect(link.host, '127.0.0.1');
    expect(link.port, 8080);
    expect(link.serverFingerprint.length, 44, reason: '32 bytes in base64');
    expect(link.token.length, 22, reason: '16 bytes in base64url without padding');
    expect(link.authority, '127.0.0.1:8080');
  });

  test('accepts the bare fragment, because a person may paste only that', () {
    final whole = PairingLink.parse(fromServer);
    final fragment = PairingLink.parse(fromServer.split('#').last);
    expect(fragment.host, whole.host);
    expect(fragment.token, whole.token);
  });

  test('round-trips through encode, so an invite can be shown again', () {
    final link = PairingLink.parse(fromServer);
    expect(PairingLink.parse(link.encode()).encode(), link.encode());
  });

  group('every address type survives a round trip', () {
    const fingerprint = 'A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=';
    const token = 'AAECAwQFBgcICQoLDA0ODw';

    for (final host in ['192.168.1.7', '2001:db8:0:0:0:0:0:1', 'nox.example.org']) {
      test(host, () {
        final built = PairingLink(host: host, port: 443, serverFingerprint: fingerprint, token: token).encode();
        final parsed = PairingLink.parse(built);
        expect(parsed.host, host);
        expect(parsed.port, 443);
        expect(parsed.serverFingerprint, fingerprint);
        expect(parsed.token, token);
      });
    }
  });

  group('refusals are distinguishable, because the person acts differently', () {
    test('a truncated link is malformed', () {
      expect(
        () => PairingLink.parse(fromServer.substring(0, fromServer.length - 20)),
        throwsA(predicate<PairingLinkException>((e) => e.error == PairingLinkError.malformed)),
      );
    });

    test('something that is not a link at all is malformed', () {
      expect(
        () => PairingLink.parse('just some text'),
        throwsA(predicate<PairingLinkException>((e) => e.error == PairingLinkError.malformed)),
      );
    });

    test('an empty string is malformed', () {
      expect(() => PairingLink.parse('   '), throwsA(predicate<PairingLinkException>((e) => e.error == PairingLinkError.malformed)));
    });

    test('a future version is refused rather than guessed at', () {
      // Reading a newer layout under a known version would produce a
      // plausible-looking address pointing anywhere at all. Version 3 is the
      // first one this build does not know, so it is the one that has to fail.
      for (final version in [3, 99]) {
        final bytes = List<int>.from(_decode(fromServer));
        bytes[0] = version;
        expect(
          () => PairingLink.parse(_encode(bytes)),
          throwsA(predicate<PairingLinkException>((e) => e.error == PairingLinkError.unsupportedVersion)),
          reason: 'version $version',
        );
      }
    });

    test('an unknown address type is a newer shape, not a broken link', () {
      final bytes = List<int>.from(_decode(fromServer));
      bytes[1] = 9;
      expect(
        () => PairingLink.parse(_encode(bytes)),
        throwsA(predicate<PairingLinkException>((e) => e.error == PairingLinkError.unsupportedVersion)),
      );
    });
  });

  group('version 2, the onion invite (contract §8A, server phase 039)', () {
    // Built by the Go server's BuildPairingLinkV2 and pinned there too
    // (TestTheOnionLinkVectorsTheAppPins), so a change on either side breaks
    // both. Every field is a different run of bytes: lengths alone would not
    // notice two fields swapped.
    const ipv4 =
        'https://nox.app/p/#AgHAqAEKH5AAAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eH6ChoqOkpaanqKmqq6ytrq8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0-PwG7QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl8';
    const ipv6 =
        'https://nox.app/p/#AgL9AAAAAAAAAAAAAAAAAAABH5AAAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eH6ChoqOkpaanqKmqq6ytrq8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0-PwG7QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl8';
    const dns =
        'https://nox.app/p/#AgMMaG9tZS5leGFtcGxlH5AAAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eH6ChoqOkpaanqKmqq6ytrq8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0-PwG7QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl8';

    final fingerprint = base64.encode(_run(0x00, 32));
    final token = base64Url.encode(_run(0xa0, 16)).replaceAll('=', '');

    // host as the parser renders it, the link, and its exact length in bytes.
    final vectors = <(String, String, int)>[
      ('192.168.1.10', ipv4, 122),
      ('fd00:0:0:0:0:0:0:1', ipv6, 134),
      ('home.example', dns, 119 + 'home.example'.length),
    ];

    for (final (host, raw, length) in vectors) {
      test('reads every field of a link the server built ($host)', () {
        final link = PairingLink.parse(raw);
        expect(link.host, host);
        expect(link.port, 8080);
        expect(link.serverFingerprint, fingerprint);
        expect(link.token, token);
        expect(link.onionPub, _run(0x20, 32));
        expect(link.onionPort, 443);
        expect(link.oneTimePriv, _run(0x40, 32));
        expect(link.carriesOnion, isTrue);
      });

      test('is exactly $length bytes ($host)', () {
        expect(_decode(raw).length, length);
      });

      test('encodes byte for byte what the server builds ($host)', () {
        final built = PairingLink(
          host: host,
          port: 8080,
          serverFingerprint: fingerprint,
          token: token,
          onionPub: _run(0x20, 32),
          onionPort: 443,
          oneTimePriv: _run(0x40, 32),
        );
        expect(built.encode(), raw);
      });
    }

    test('the IPv4 link is the 163 characters the contract states', () {
      expect(ipv4.split('#').last.length, 163);
    });

    test('a version-2 link cut short is malformed, not read as version 1', () {
      // Without its onion tail the bytes are exactly a version-1 link with the
      // wrong version byte - reading them as one would hand the person a link
      // that silently stopped working away from home.
      final bytes = _decode(ipv4);
      for (final cut in [1, 34, 66]) {
        expect(
          () => PairingLink.parse(_encode(bytes.sublist(0, bytes.length - cut))),
          throwsA(predicate<PairingLinkException>((e) => e.error == PairingLinkError.malformed)),
          reason: '$cut bytes short',
        );
      }
    });

    test('a version-1 link with an onion tail glued on is malformed', () {
      final bytes = List<int>.from(_decode(ipv4));
      bytes[0] = PairingLink.version;
      expect(
        () => PairingLink.parse(_encode(bytes)),
        throwsA(predicate<PairingLinkException>((e) => e.error == PairingLinkError.malformed)),
      );
    });

    test('a version-1 link has no onion part, and still encodes as version 1', () {
      final link = PairingLink.parse(fromServer);
      expect(link.onionPub, isNull);
      expect(link.onionPort, isNull);
      expect(link.oneTimePriv, isNull);
      expect(link.carriesOnion, isFalse);
      expect(_decode(link.encode()).first, PairingLink.version);
      expect(link.encode(), fromServer);
    });
  });

  test('the token type is nowhere in the link', () {
    // By construction: there is no field for it. A stolen link must not be
    // able to announce whether it grants ownership.
    final link = PairingLink.parse(fromServer);
    expect(link.encode().length, PairingLink.parse(link.encode()).encode().length);
    expect(_decode(fromServer).length, 56, reason: 'version + type + IPv4 + port + key + token, nothing else');
  });
}

List<int> _decode(String link) {
  final fragment = link.split('#').last;
  return base64Url.decode(base64Url.normalize(fragment));
}

String _encode(List<int> bytes) => 'https://nox.app/p/#${base64Url.encode(bytes).replaceAll('=', '')}';

/// [length] bytes counting up from [from] - the shape of every field in the
/// server's vectors.
Uint8List _run(int from, int length) => Uint8List.fromList([for (var i = 0; i < length; i++) from + i]);
