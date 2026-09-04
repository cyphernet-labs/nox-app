import 'dart:convert';

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
    expect(link.serverKey.length, 44, reason: '32 bytes in base64');
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
    const key = 'A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=';
    const token = 'AAECAwQFBgcICQoLDA0ODw';

    for (final host in ['192.168.1.7', '2001:db8:0:0:0:0:0:1', 'nox.example.org']) {
      test(host, () {
        final built = PairingLink(host: host, port: 443, serverKey: key, token: token).encode();
        final parsed = PairingLink.parse(built);
        expect(parsed.host, host);
        expect(parsed.port, 443);
        expect(parsed.serverKey, key);
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
      // Reading a newer layout under this version would produce a
      // plausible-looking address pointing anywhere at all.
      final bytes = List<int>.from(_decode(fromServer));
      bytes[0] = 99;
      expect(
        () => PairingLink.parse(_encode(bytes)),
        throwsA(predicate<PairingLinkException>((e) => e.error == PairingLinkError.unsupportedVersion)),
      );
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
