import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/remote/socket/server_addresses_parser.dart';

/// Reading `addresses` - the greeting's field and the `server.addresses`
/// payload (contract §3, §8A) - leniently and safely.
void main() {
  final onion = '${'a' * 56}.onion:443';

  test('the contract example reads as written', () {
    final parsed = ServerAddressesParser.parse({
      'direct': ['192.168.1.20:8080', '[fd12:3456::20]:8080'],
      'onion': onion,
    })!;

    expect(parsed.direct, ['192.168.1.20:8080', '[fd12:3456::20]:8080']);
    expect(parsed.onion, onion);
    expect(parsed.onionHost, '${'a' * 56}.onion');
    expect(parsed.onionPort, 443);
  });

  test('not an object is no statement at all - a server older than 039', () {
    expect(ServerAddressesParser.parse(null), isNull);
    expect(ServerAddressesParser.parse('192.168.1.20:8080'), isNull);
    expect(ServerAddressesParser.parse(const ['192.168.1.20:8080']), isNull);
  });

  test('entries that are not host:port are dropped, the rest kept', () {
    final parsed = ServerAddressesParser.parse({
      'direct': ['192.168.1.20:8080', 'no-port', 42, '', 'user@host:1', 'host:0', 'host:70000', 'a/b:1', '192.168.1.20:8080'],
    })!;

    expect(parsed.direct, ['192.168.1.20:8080']);
  });

  test('no more than sixteen direct addresses are taken', () {
    final parsed = ServerAddressesParser.parse({
      'direct': [for (var i = 1; i <= 20; i++) '10.0.0.$i:8080'],
    })!;

    expect(parsed.direct, hasLength(ServerAddressesParser.maxDirect));
    expect(parsed.direct.first, '10.0.0.1:8080', reason: 'the most preferred are kept');
  });

  test('only a v3 onion address is an onion address (FR-008)', () {
    for (final bad in ['example.com:443', '${'a' * 55}.onion:443', '${'1' * 56}.onion:443', 'x.onion', 42, '${'a' * 56}.onion:0']) {
      expect(ServerAddressesParser.parse({'onion': bad})!.onion, isNull, reason: '$bad');
    }
  });

  test('an onion address without a port gets the service port, and letters are folded', () {
    expect(ServerAddressesParser.parse({'onion': '${'A' * 56}.ONION'})!.onion, '${'a' * 56}.onion:443');
  });

  test('the public address is read when it is host:port, and dropped otherwise (phase 045)', () {
    expect(ServerAddressesParser.parse({'public': 'nox.example.org:8443'})!.public, 'nox.example.org:8443');
    expect(ServerAddressesParser.parse({'public': '[2001:db8::7]:8443'})!.public, '[2001:db8::7]:8443');
    for (final bad in ['nox.example.org', 'host:0', 42, '', onion, 'a/b:1']) {
      expect(ServerAddressesParser.parse({'public': bad})!.public, isNull, reason: '$bad');
    }
    expect(ServerAddressesParser.parse({'direct': <String>[]})!.public, isNull, reason: 'absent when the server has none');
  });
}
