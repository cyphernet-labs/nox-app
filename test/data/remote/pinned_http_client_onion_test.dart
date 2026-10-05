import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/remote/pinned_http_client.dart';
import 'package:nox_app/domain/service/tor_service.dart';

/// The onion path through the pinned client (phase 040): the client dials the
/// Tor bridge on loopback, presents its secret, and does TLS to the onion host
/// over it - and the fingerprint is checked exactly as on the direct path.
///
/// The "bridge" here is a loopback relay standing in for the Rust one: it
/// checks the secret and pipes bytes to a TLS server built from the fixtures.
const String _fixtures = 'test/general/pairing/fixtures';
final String _onion = '${'a' * 56}.onion';

String get _fingerprint => File('$_fixtures/fingerprint.txt').readAsStringSync().trim();

Future<HttpServer> _server({required bool honest}) async {
  final context = SecurityContext()
    ..useCertificateChainBytes(File('$_fixtures/${honest ? 'valid' : 'stranger'}.pem').readAsBytesSync())
    ..usePrivateKeyBytes(File('$_fixtures/${honest ? 'server_key' : 'stranger_key'}.pem').readAsBytesSync());
  final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
  server.listen((request) {
    request.response
      ..statusCode = HttpStatus.ok
      ..write('host=${request.headers.host}');
    request.response.close();
  });
  return server;
}

/// A loopback relay that admits a connection only after [secret].
Future<ServerSocket> _bridge(Uint8List secret, int targetPort) async {
  final bridge = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  bridge.listen((client) async {
    final received = <int>[];
    Socket? upstream;
    late StreamSubscription<Uint8List> sub;
    sub = client.listen((chunk) async {
      if (upstream != null) {
        upstream!.add(chunk);
        return;
      }
      received.addAll(chunk);
      if (received.length < 32) return;
      final presented = received.sublist(0, 32);
      if (!const ListEqualityShim().equals(presented, secret)) {
        await client.close();
        await sub.cancel();
        return;
      }
      sub.pause();
      upstream = await Socket.connect(InternetAddress.loopbackIPv4, targetPort);
      upstream!.listen(client.add, onDone: client.destroy);
      if (received.length > 32) upstream!.add(received.sublist(32));
      sub.resume();
    }, onDone: () => upstream?.destroy());
  });
  return bridge;
}

class ListEqualityShim {
  const ListEqualityShim();

  bool equals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

Future<String> _get(PinnedHttpClient pinned) async {
  final request = await pinned.client.getUrl(Uri.parse('https://$_onion/health'));
  final response = await request.close();
  return utf8.decodeStream(response);
}

void main() {
  late HttpOverrides? saved;
  setUpAll(() {
    saved = HttpOverrides.current;
    HttpOverrides.global = null;
  });
  tearDownAll(() => HttpOverrides.global = saved);

  final secret = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

  test('an onion host goes through the bridge and reaches the pinned server', () async {
    final server = await _server(honest: true);
    final bridge = await _bridge(secret, server.port);
    addTearDown(() async {
      await bridge.close();
      await server.close(force: true);
    });
    final pinned = PinnedHttpClient()
      ..pinTo(_fingerprint)
      ..onionBridge = () => TorBridgeEndpoint(port: bridge.port, secret: secret);

    final body = await _get(pinned);
    expect(body, startsWith('host=$_onion'), reason: 'the request names the onion host, as the server expects');
    expect(pinned.refusals, 0);
  });

  test('a server on another key is refused through Tor as well (FR-030)', () async {
    final server = await _server(honest: false);
    final bridge = await _bridge(secret, server.port);
    addTearDown(() async {
      await bridge.close();
      await server.close(force: true);
    });
    final pinned = PinnedHttpClient()
      ..pinTo(_fingerprint)
      ..onionBridge = () => TorBridgeEndpoint(port: bridge.port, secret: secret);

    await expectLater(_get(pinned), throwsA(anything));
    expect(pinned.refusals, 1);
  });

  test('a wrong secret is turned away by the bridge before any TLS', () async {
    final server = await _server(honest: true);
    final bridge = await _bridge(secret, server.port);
    addTearDown(() async {
      await bridge.close();
      await server.close(force: true);
    });
    final wrong = Uint8List.fromList(secret)..[0] ^= 1;
    final pinned = PinnedHttpClient()
      ..pinTo(_fingerprint)
      ..onionBridge = () => TorBridgeEndpoint(port: bridge.port, secret: wrong);

    await expectLater(_get(pinned), throwsA(anything));
    expect(pinned.refusals, 0, reason: 'nothing was presented to check');
  });

  test('without a bridge an onion host is not dialled at all', () async {
    final pinned = PinnedHttpClient()..pinTo(_fingerprint);
    await expectLater(_get(pinned), throwsA(isA<SocketException>()));
  });
}
