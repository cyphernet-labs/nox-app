import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/connection/server_addresses.dart';

void main() {
  test('direct candidates go last-good first, then the server list, then the link, each once', () {
    const addresses = ServerAddresses(direct: ['192.168.1.20:8443', '10.0.0.5:8443'], lastGood: '10.0.0.5:8443');
    expect(addresses.candidates('nox.local:8443'), ['10.0.0.5:8443', '192.168.1.20:8443', 'nox.local:8443']);
    expect(addresses.candidates('192.168.1.20:8443'), ['10.0.0.5:8443', '192.168.1.20:8443']);
    expect(ServerAddresses.empty.candidates(null), isEmpty);
    expect(ServerAddresses.empty.candidates('host:1'), ['host:1']);
  });

  test('the onion address splits into host and port, 443 when unsaid', () {
    const withPort = ServerAddresses(onion: 'abc.onion:443');
    expect(withPort.onionHost, 'abc.onion');
    expect(withPort.onionPort, 443);
    const odd = ServerAddresses(onion: 'abc.onion:8443');
    expect(odd.onionPort, 8443);
    expect(ServerAddresses.empty.onionHost, isNull);
  });

  group('the connection settings (phase 045)', () {
    test('the server address field shows the person\'s edit, else the public address, else the link\'s', () {
      expect(ServerAddresses.empty.fieldAddress('192.168.1.20:8443'), '192.168.1.20:8443');
      expect(const ServerAddresses(public: 'nox.example.org:8443').fieldAddress('192.168.1.20:8443'), 'nox.example.org:8443');
      expect(
        const ServerAddresses(public: 'nox.example.org:8443', manualAddress: '10.8.0.2:8443').fieldAddress('192.168.1.20:8443'),
        '10.8.0.2:8443',
      );
      expect(ServerAddresses.empty.fieldAddress(null), isNull);
    });

    test('the onion address in effect is the person\'s edit, else the server\'s; a cleared field means none', () {
      final server = '${'a' * 56}.onion:443';
      final typed = '${'b' * 56}.onion:443';
      expect(ServerAddresses(onion: server).effectiveOnion, server);
      expect(ServerAddresses(onion: server, manualOnion: typed).effectiveOnion, typed);
      expect(ServerAddresses(onion: server, manualOnion: typed).onionHost, '${'b' * 56}.onion');
      expect(ServerAddresses(onion: server, manualOnion: '').effectiveOnion, isNull);
      expect(ServerAddresses(onion: server, manualOnion: '').onionHost, isNull);
      expect(ServerAddresses.empty.effectiveOnion, isNull);
    });

    test('direct candidates: last good, the person\'s, the public one, the server\'s list, the link - each once', () {
      const addresses = ServerAddresses(
        direct: ['192.168.1.20:8443', '203.0.113.7:8443'],
        public: '203.0.113.7:8443',
        manualAddress: '10.8.0.2:8443',
        lastGood: '192.168.1.20:8443',
      );
      expect(addresses.candidates('nox.local:8443'), ['192.168.1.20:8443', '10.8.0.2:8443', '203.0.113.7:8443', 'nox.local:8443']);
    });

    test('Use Tor is off unless turned on', () {
      expect(ServerAddresses.empty.useTor, isFalse);
    });
  });
}
