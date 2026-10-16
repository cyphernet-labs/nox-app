import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/pairing/pairing_link.dart';

/// The contract's vectors (specs/044-secure-channel/contracts/link-vectors.json),
/// shared with the Go server: a link the two sides agree on is the only kind
/// worth testing.
final Map<String, dynamic> _vectors =
    jsonDecode(File('test/general/pairing/fixtures/link-vectors.json').readAsStringSync()) as Map<String, dynamic>;

Uint8List _hex(String hex) => Uint8List.fromList([for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);

Matcher _refused(PairingLinkError error) => throwsA(predicate<PairingLinkException>((e) => e.error == error, 'refused as ${error.name}'));

/// Checks [link] against a vector's addresses, in order.
void _expectAddresses(PairingLink link, List<dynamic> expected) {
  expect(link.addresses, hasLength(expected.length));
  for (var i = 0; i < expected.length; i++) {
    final want = expected[i] as Map<String, dynamic>;
    final got = link.addresses[i];
    switch (want['type']) {
      case 'onion':
        expect(got, isA<OnionLinkAddress>());
        expect((got as OnionLinkAddress).servicePublicKey, _hex(want['public_key'] as String));
        expect(got.port, want['port']);
      case final String type:
        expect(got, isA<DirectLinkAddress>());
        final direct = got as DirectLinkAddress;
        expect(direct.kind.name, type);
        expect(direct.host, want['host']);
        expect(direct.port, want['port']);
    }
  }
}

void main() {
  group('the contract vectors', () {
    test('full: the server key, the token and three addresses in order', () {
      final vector = _vectors['full'] as Map<String, dynamic>;
      final link = PairingLink.parse(vector['link'] as String);
      expect(link.serverKey, _hex(vector['server_public_key'] as String));
      expect(base64Url.decode(base64Url.normalize(link.token)), _hex(vector['token'] as String));
      expect(link.token, isNot(contains('=')), reason: 'base64url without padding - the form pair sends');
      _expectAddresses(link, vector['addresses'] as List<dynamic>);
      expect(link.directAddresses, ['192.168.1.20:8443', 'nox.example.org:8443']);
      expect(link.onionServiceKey, _hex('17cb79fb2b4120f2b1ec65e4198d6e08b28e813feb01e4a400839b85e18080ce'));
    });

    test('minimal: one IPv4 address and no onion', () {
      final vector = _vectors['minimal'] as Map<String, dynamic>;
      final link = PairingLink.parse(vector['link'] as String);
      _expectAddresses(link, vector['addresses'] as List<dynamic>);
      expect(link.onionServiceKey, isNull);
    });

    test('an address of a type this build does not know is skipped by its length', () {
      final vector = _vectors['unknown_type_skipped'] as Map<String, dynamic>;
      _expectAddresses(PairingLink.parse(vector['link'] as String), vector['addresses'] as List<dynamic>);
    });

    test('every malformed vector is malformed - an old-format link among them', () {
      final refusals = _vectors['refusals'] as Map<String, dynamic>;
      for (final raw in (refusals['malformed'] as List<dynamic>).cast<String>()) {
        expect(() => PairingLink.parse(raw), _refused(PairingLinkError.malformed), reason: raw);
      }
    });

    test('a newer version asks for an update, not for a new link', () {
      final refusals = _vectors['refusals'] as Map<String, dynamic>;
      expect(() => PairingLink.parse(refusals['newer_version'] as String), _refused(PairingLinkError.newerVersion));
    });

    test('the demo link is a readable one', () {
      expect(PairingLink.tryParse(PairingLink.demo), isNotNull);
    });
  });

  group('the rules beyond the vectors', () {
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
    const token = 'AAECAwQFBgcICQoLDA0ODw';

    PairingLink link(List<LinkAddress> addresses) => PairingLink(serverKey: key, token: token, addresses: addresses);

    /// The link's bytes with [tail] in place of the addresses.
    String raw(List<int> tail, {int version = 3}) =>
        PairingLink.prefix +
        base64Url.encode([version, ...key, ...base64Url.decode(base64Url.normalize(token)), ...tail]).replaceAll('=', '');

    test('every address kind survives a round trip, in order', () {
      final built = link([
        const DirectLinkAddress(kind: DirectAddressKind.ipv4, host: '10.0.0.5', port: 9000),
        const DirectLinkAddress(kind: DirectAddressKind.ipv6, host: '2001:db8::1', port: 443),
        const DirectLinkAddress(kind: DirectAddressKind.name, host: 'nox.example.org', port: 8443),
        OnionLinkAddress(Uint8List(32)..[0] = 7),
      ]);
      final parsed = PairingLink.parse(built.encode());
      expect(parsed.addresses, built.addresses);
      expect(parsed.directAddresses, ['10.0.0.5:9000', '[2001:db8::1]:443', 'nox.example.org:8443']);
      expect(parsed.serverKeyBase64, base64.encode(key));
      expect(parsed.token, token);
    });

    test('surrounding whitespace is forgiven, a different scheme is not', () {
      final text = link([const DirectLinkAddress(kind: DirectAddressKind.ipv4, host: '10.0.0.5', port: 9000)]).encode();
      expect(PairingLink.tryParse('  $text\n'), isNotNull);
      expect(() => PairingLink.parse(text.replaceFirst('nox://pair/', 'nox://id/')), _refused(PairingLinkError.malformed));
      expect(() => PairingLink.parse('$text='), _refused(PairingLinkError.malformed), reason: 'base64url without padding');
    });

    test('a link with no address it can use is malformed', () {
      expect(() => PairingLink.parse(raw([])), _refused(PairingLinkError.malformed));
      expect(() => PairingLink.parse(raw([9, 1, 0])), _refused(PairingLinkError.malformed), reason: 'only an unknown type');
    });

    test('a known type with the wrong length, port 0 or an empty name is malformed', () {
      expect(() => PairingLink.parse(raw([1, 5, 10, 0, 0, 5, 1])), _refused(PairingLinkError.malformed));
      expect(() => PairingLink.parse(raw([1, 6, 10, 0, 0, 5, 0, 0])), _refused(PairingLinkError.malformed));
      expect(() => PairingLink.parse(raw([3, 2, 0x01, 0xBB])), _refused(PairingLinkError.malformed));
      expect(() => PairingLink.parse(raw([3, 3, 0xFF, 0x01, 0xBB])), _refused(PairingLinkError.malformed), reason: 'not UTF-8');
      expect(() => PairingLink.parse(raw([4, 31, ...List<int>.filled(31, 1)])), _refused(PairingLinkError.malformed));
    });

    test('an incomplete header or a length past the end is malformed', () {
      expect(() => PairingLink.parse(raw([1, 6, 10, 0, 0, 5, 0x23, 0x28, 1])), _refused(PairingLinkError.malformed));
      expect(() => PairingLink.parse(raw([1, 9, 10, 0, 0, 5, 0x23, 0x28])), _refused(PairingLinkError.malformed));
    });

    test('a version below 3 is malformed, and one above it asks for an update', () {
      final ipv4 = [1, 6, 10, 0, 0, 5, 0x23, 0x28];
      expect(() => PairingLink.parse(raw(ipv4, version: 2)), _refused(PairingLinkError.malformed));
      expect(() => PairingLink.parse(raw(ipv4, version: 4)), _refused(PairingLinkError.newerVersion));
      expect(PairingLink.refusalOf(raw(ipv4, version: 4)), PairingLinkError.newerVersion);
      expect(PairingLink.isPairingLink(raw(ipv4, version: 4)), isTrue, reason: 'still a link: the scanner hands it on');
      expect(PairingLink.isPairingLink('https://nox.app/p/#AQF_AAAB'), isFalse);
      expect(PairingLink.refusalOf(raw(ipv4)), isNull);
    });
  });
}
