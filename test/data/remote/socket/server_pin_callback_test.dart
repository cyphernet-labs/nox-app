import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/remote/pinned_http_client.dart';

/// Tolerance, proved through a real handshake.
///
/// The pure check over `cert.der` cannot see a name, a date or an issuer at
/// all — structurally, there is nothing in it that could refuse on them — so a
/// test at that level cannot fail and therefore proves nothing. These run a
/// local HTTPS server on the RIGHT key and let the platform's TLS stack form
/// its own opinion first; what is asserted is that the connection is made
/// anyway.
const String _fixtures = 'test/general/pairing/fixtures';

String get _fingerprint => File('$_fixtures/fingerprint.txt').readAsStringSync().trim();

/// The other machine's fingerprint, read off its certificate the same way the
/// app reads one off a pairing link.
String get _strangerFingerprint {
  final der = File('$_fixtures/stranger.der').readAsBytesSync();
  final start = _indexOfP256Spki(der);
  return base64.encode(sha256.convert(der.sublist(start, start + 91)).bytes);
}

const List<int> _p256Header = <int>[
  0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, //
  0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, //
  0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, //
  0x42, 0x00,
];

int _indexOfP256Spki(List<int> der) {
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
  throw StateError('the stranger fixture has no P-256 key in it');
}

/// Serves one request over TLS with the given certificate chain and key.
Future<HttpServer> _serve(String chainPem, String keyPem) async {
  final context = SecurityContext()
    ..useCertificateChainBytes(File('$_fixtures/$chainPem').readAsBytesSync())
    ..usePrivateKeyBytes(File('$_fixtures/$keyPem').readAsBytesSync());
  final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
  server.listen((HttpRequest request) {
    request.response
      ..statusCode = HttpStatus.ok
      ..write('ok');
    request.response.close();
  });
  return server;
}

Future<int> _statusFrom(HttpServer server, PinnedHttpClient client) async {
  final request = await client.client.getUrl(Uri.parse('https://127.0.0.1:${server.port}/'));
  final response = await request.close();
  await response.drain<void>();
  return response.statusCode;
}

void main() {
  // The Flutter test binding installs HttpOverrides that answer every request
  // with a 400 so a test cannot reach the network by accident. This file's
  // whole subject is a real TLS handshake against a server it starts itself,
  // on loopback, so the override is lifted for the duration.
  late HttpOverrides? saved;
  setUpAll(() {
    saved = HttpOverrides.current;
    HttpOverrides.global = null;
  });
  tearDownAll(() => HttpOverrides.global = saved);

  group('a certificate on the right key is accepted whatever else is wrong with it', () {
    for (final tc in <({String name, String chain, String why})>[
      (name: 'an ordinary one', chain: 'valid.pem', why: 'the plain case'),
      (
        name: 'one that expired in 2020',
        chain: 'expired.pem',
        why: 'a home server whose owner has not touched it for years still has to answer',
      ),
      (name: 'one naming mail.example.com', chain: 'wrong_name.pem', why: 'a home server has no name of its own and its address changes'),
      (
        name: 'one signed by an authority nothing trusts',
        chain: 'unknown_issuer.pem',
        why: 'trust comes from the link a person carried, not from an issuer',
      ),
    ]) {
      test('${tc.name} is accepted, because ${tc.why}', () async {
        final server = await _serve(tc.chain, 'server_key.pem');
        addTearDown(() => server.close(force: true));
        final client = PinnedHttpClient()..pinTo(_fingerprint);

        expect(await _statusFrom(server, client), HttpStatus.ok);
        expect(client.refusals, 0);
      });
    }
  });

  test('a certificate that PLANTS the right key ahead of its own is refused by a real handshake', () async {
    // The whole attack, end to end: this server holds ONLY the foreign private
    // key, and its certificate carries a verbatim copy of the right key's
    // SubjectPublicKeyInfo in the subject - ahead of its own key, where the
    // DER field order puts the subject. Accepting it hands both transports to
    // a machine that cannot prove it is the paired one.
    final server = await _serve('planted.pem', 'stranger_key.pem');
    addTearDown(() => server.close(force: true));
    final client = PinnedHttpClient()..pinTo(_fingerprint);

    await expectLater(_statusFrom(server, client), throwsA(isA<HandshakeException>()));
    expect(client.refusals, 1);
  });

  test('a perfectly well-formed certificate on ANOTHER key is refused', () async {
    final server = await _serve('stranger.pem', 'stranger_key.pem');
    addTearDown(() => server.close(force: true));
    final client = PinnedHttpClient()..pinTo(_fingerprint);

    await expectLater(_statusFrom(server, client), throwsA(isA<HandshakeException>()));
    expect(client.refusals, 1, reason: 'the refusal has to be visible, or nothing upstream can tell it from a dead network');
  });

  test('a client with nothing pinned refuses the right server (FR-009)', () async {
    // "No fingerprint" must never mean "accept anything". An install with
    // nothing to compare against is exactly the one that must not connect.
    final server = await _serve('valid.pem', 'server_key.pem');
    addTearDown(() => server.close(force: true));
    final client = PinnedHttpClient();

    await expectLater(_statusFrom(server, client), throwsA(isA<HandshakeException>()));
    expect(client.refusals, 1);
  });

  test('unpinning takes the right away again, so a logout really disconnects', () async {
    final server = await _serve('valid.pem', 'server_key.pem');
    addTearDown(() => server.close(force: true));
    final client = PinnedHttpClient()..pinTo(_fingerprint);
    expect(await _statusFrom(server, client), HttpStatus.ok);

    client.unpin();

    // Not just the value: the pooled connection has to go too. A kept-alive
    // connection performs no handshake, so nothing would ever re-check it and
    // a logged-out app would go on talking to the server it was logged out of.
    await expectLater(_statusFrom(server, client), throwsA(isA<HandshakeException>()));
  });

  test('re-pairing to another server stops reaching the previous one', () async {
    final first = await _serve('valid.pem', 'server_key.pem');
    addTearDown(() => first.close(force: true));
    final client = PinnedHttpClient()..pinTo(_fingerprint);
    expect(await _statusFrom(first, client), HttpStatus.ok);

    // The person pairs with a different machine. The old server is still up and
    // still reachable at its address - and must stop being talked to.
    client.pinTo(_strangerFingerprint);

    await expectLater(_statusFrom(first, client), throwsA(isA<HandshakeException>()));

    final second = await _serve('stranger.pem', 'stranger_key.pem');
    addTearDown(() => second.close(force: true));
    expect(await _statusFrom(second, client), HttpStatus.ok);
  });

  test('a server presenting a CHAIN cannot be pinned, and this is where that is written down', () async {
    // Measured, not assumed: the platform hands the callback the TOP of the
    // presented chain, so for leaf + authority it is the AUTHORITY key that
    // arrives - and the server's own key is never seen at all.
    //
    // Nothing in this product presents a chain: the server issues itself one
    // self-signed certificate and presents that alone, which is why every case
    // above works. This test exists so that a change to the server making it
    // present a chain fails HERE, loudly, instead of in somebody's hands.
    final server = await _serve('unknown_issuer_chain.pem', 'server_key.pem');
    addTearDown(() => server.close(force: true));
    final client = PinnedHttpClient()..pinTo(_fingerprint);

    await expectLater(_statusFrom(server, client), throwsA(isA<HandshakeException>()));
  });

  test('the pin is re-read at handshake time, not captured when the client was built', () async {
    // The client is a DI singleton that outlives pairing, re-pairing and
    // logout. A naive implementation reads the fingerprint once at
    // construction - and on a fresh install that value is nothing at all.
    final client = PinnedHttpClient();
    final firstUse = client.client; // built here, before anything is pinned
    expect(firstUse, isNotNull);

    final server = await _serve('valid.pem', 'server_key.pem');
    addTearDown(() => server.close(force: true));

    client.pinTo(_fingerprint);
    expect(await _statusFrom(server, client), HttpStatus.ok);
  });
}
