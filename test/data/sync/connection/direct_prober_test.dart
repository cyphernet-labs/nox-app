import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/sync/connection/direct_prober.dart';

/// The direct probe against real TLS on loopback: the honest server from the
/// pairing fixtures, a stranger on another key, a port nobody listens on, and
/// a listener that never answers (phase 040, FR-001, FR-002, FR-005).
const String _fixtures = 'test/general/pairing/fixtures';

String get _fingerprint => File('$_fixtures/fingerprint.txt').readAsStringSync().trim();

Future<HttpServer> _server({required bool honest, int status = HttpStatus.ok}) async {
  final context = SecurityContext()
    ..useCertificateChainBytes(File('$_fixtures/${honest ? 'valid' : 'stranger'}.pem').readAsBytesSync())
    ..usePrivateKeyBytes(File('$_fixtures/${honest ? 'server_key' : 'stranger_key'}.pem').readAsBytesSync());
  final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
  server.listen((request) {
    request.response.statusCode = request.uri.path == '/health' ? status : HttpStatus.notFound;
    request.response.close();
  });
  return server;
}

/// A port that accepts and then says nothing at all.
Future<ServerSocket> _silent() async {
  final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  listener.listen((_) {});
  return listener;
}

Future<int> _closedPort() async {
  final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = probe.port;
  await probe.close();
  return port;
}

void main() {
  late HttpOverrides? saved;
  setUpAll(() {
    saved = HttpOverrides.current;
    HttpOverrides.global = null;
  });
  tearDownAll(() => HttpOverrides.global = saved);

  final prober = TlsDirectProber();

  test('the server on its own key answers, and wins', () async {
    final server = await _server(honest: true);
    addTearDown(() => server.close(force: true));

    final result = await prober.probe(['127.0.0.1:${server.port}'], fingerprint: _fingerprint);

    expect(result.address, '127.0.0.1:${server.port}');
    expect(result.notHome, isEmpty);
  });

  test('another key is "not home", never a win (FR-005)', () async {
    final stranger = await _server(honest: false);
    addTearDown(() => stranger.close(force: true));

    final result = await prober.probe(['127.0.0.1:${stranger.port}'], fingerprint: _fingerprint);

    expect(result.address, isNull);
    expect(result.notHome, ['127.0.0.1:${stranger.port}']);
  });

  test('the right key with an unhealthy /health is not a way home', () async {
    final sick = await _server(honest: true, status: HttpStatus.serviceUnavailable);
    addTearDown(() => sick.close(force: true));

    final result = await prober.probe(['127.0.0.1:${sick.port}'], fingerprint: _fingerprint);

    expect(result.address, isNull);
    expect(result.notHome, isEmpty);
  });

  test('a dead first candidate hands over to the rest without waiting out its head start', () async {
    final dead = await _closedPort();
    final stranger = await _server(honest: false);
    final home = await _server(honest: true);
    addTearDown(() async {
      await stranger.close(force: true);
      await home.close(force: true);
    });

    final watch = Stopwatch()..start();
    final result = await prober.probe([
      '127.0.0.1:$dead',
      '127.0.0.1:${stranger.port}',
      '127.0.0.1:${home.port}',
    ], fingerprint: _fingerprint);

    expect(result.address, '127.0.0.1:${home.port}');
    expect(watch.elapsed, lessThan(TlsDirectProber.budget));
  });

  test('a listener that never answers costs one attempt, not the round', () async {
    final silent = await _silent();
    final home = await _server(honest: true);
    addTearDown(() async {
      await silent.close();
      await home.close(force: true);
    });

    final result = await prober.probe(['127.0.0.1:${silent.port}', '127.0.0.1:${home.port}'], fingerprint: _fingerprint);

    expect(result.address, '127.0.0.1:${home.port}');
  });

  test('nothing answering ends within the budget, so Tor is not kept waiting (FR-002)', () async {
    final silent = await _silent();
    addTearDown(silent.close);

    final watch = Stopwatch()..start();
    final result = await prober.probe(['127.0.0.1:${silent.port}'], fingerprint: _fingerprint);

    expect(result.address, isNull);
    expect(watch.elapsed, lessThan(TlsDirectProber.budget + const Duration(milliseconds: 500)));
  });

  test('no candidates, or nothing to check against, is no address', () async {
    expect((await prober.probe(const [], fingerprint: _fingerprint)).address, isNull);
    expect((await prober.probe(const ['127.0.0.1:1'], fingerprint: '')).address, isNull);
  });
}
