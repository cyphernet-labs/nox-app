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
}
