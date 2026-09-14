import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/remote/api_client.dart';
import 'package:nox_app/data/remote/pinned_http_client.dart';
import 'package:nox_app/data/remote/socket/socket_channel_factory.dart';
import 'package:nox_app/domain/model/app_config/app_config.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_app/domain/model/app_config/server_limits.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';

/// The gate's one guard on the thing this whole feature is: that BOTH
/// transports actually go through the pin.
///
/// Written because they did not. Every other test here exercises
/// `PinnedHttpClient` directly, and the two places that hand it to a transport
/// were covered only by a type check (`isA<IOHttpClientAdapter>()`) and by
/// nothing at all. Both could be replaced with an unpinned client and the whole
/// suite stayed green while attachment bytes arrived from a stranger.
///
/// So these dial a real hostile server through the REAL seams — `ApiClient` for
/// bytes, `WebSocketChannelFactory` for commands — and require a refusal.
const String _fixtures = 'test/general/pairing/fixtures';

String get _fingerprint => File('$_fixtures/fingerprint.txt').readAsStringSync().trim();

/// A server on a key the pairing link never named.
Future<HttpServer> _hostile() async {
  final context = SecurityContext()
    ..useCertificateChainBytes(File('$_fixtures/stranger.pem').readAsBytesSync())
    ..usePrivateKeyBytes(File('$_fixtures/stranger_key.pem').readAsBytesSync());
  final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
  server.listen((request) {
    request.response
      ..statusCode = HttpStatus.ok
      ..write('bytes from a machine nobody paired with');
    request.response.close();
  });
  return server;
}

/// The honest one, for the control.
Future<HttpServer> _honest() async {
  final context = SecurityContext()
    ..useCertificateChainBytes(File('$_fixtures/valid.pem').readAsBytesSync())
    ..usePrivateKeyBytes(File('$_fixtures/server_key.pem').readAsBytesSync());
  final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
  server.listen((request) {
    request.response
      ..statusCode = HttpStatus.ok
      ..write('ok');
    request.response.close();
  });
  return server;
}

class _Config implements AppConfigRepository {
  @override
  AppConfig get config => const AppConfig(flavor: AppFlavorType.stage);
  @override
  Future<void> initialize({required AppFlavorType flavorType}) async {}
  @override
  Future<String?> getUserAuthIdToken() async => null;
  @override
  bool get isTestEnvironment => true;
  @override
  ServerLimits get limits => ServerLimits.contractDefaults;
  @override
  void updateLimits(ServerLimits limits) {}
}

void main() {
  late HttpOverrides? saved;
  setUpAll(() {
    saved = HttpOverrides.current;
    HttpOverrides.global = null;
  });
  tearDownAll(() => HttpOverrides.global = saved);

  group('the file transport', () {
    test('refuses a server the link never named', () async {
      // The mutation this catches: swapping ApiClient's adapter for one over a
      // plain HttpClient. Before this test that swap delivered attachment bytes
      // from a stranger with the whole suite green.
      final server = await _hostile();
      addTearDown(() => server.close(force: true));
      final pinned = PinnedHttpClient()..pinTo(_fingerprint);
      final api = ApiClient(_Config(), pinned)..initBase(address: 'https://127.0.0.1:${server.port}');

      await expectLater(api.dio.get<String>('/anything'), throwsA(isA<DioException>()));
      expect(pinned.refusals, 1, reason: 'refused by the pin, not by something incidental');
    });

    test('and keeps working after the pin changes', () async {
      // Dio's adapter caches the client it is given, so a pin change - which
      // throws that client away - used to leave every later transfer failing
      // for no reason anybody could see.
      final honest = await _honest();
      addTearDown(() => honest.close(force: true));
      final pinned = PinnedHttpClient()..pinTo('a-different-server-entirely=');
      final api = ApiClient(_Config(), pinned)..initBase(address: 'https://127.0.0.1:${honest.port}');
      await expectLater(api.dio.get<String>('/anything'), throwsA(isA<DioException>()));

      pinned.pinTo(_fingerprint); // the person paired with this machine

      final response = await api.dio.get<String>('/anything');
      expect(response.statusCode, HttpStatus.ok);
    });

    test('and reaches the one it did', () async {
      // The control, so the test above cannot pass by refusing everything.
      final server = await _honest();
      addTearDown(() => server.close(force: true));
      final pinned = PinnedHttpClient()..pinTo(_fingerprint);
      final api = ApiClient(_Config(), pinned)..initBase(address: 'https://127.0.0.1:${server.port}');

      final response = await api.dio.get<String>('/anything');
      expect(response.statusCode, HttpStatus.ok);
      expect(pinned.refusals, 0);
    });
  });

  group('the command transport', () {
    test('refuses a server the link never named', () async {
      // The mutation this catches: dropping `customClient:` from
      // IOWebSocketChannel.connect. Nothing in the gate covered this seam at
      // all - the only code that exercised it lived in test/live, which
      // `flutter test` never collects.
      final server = await _hostile();
      addTearDown(() => server.close(force: true));
      final pinned = PinnedHttpClient()..pinTo(_fingerprint);
      final connection = WebSocketChannelFactory(pinned).connect(Uri.parse('wss://127.0.0.1:${server.port}/ws'));

      await expectLater(connection.frames.first, throwsA(isA<ServerPinRefusedException>()));
      expect(pinned.refusals, 1);
    });

    test('and a refusal is told apart from a dead address', () async {
      // The distinction the whole of US3 rests on. A closed port must NOT look
      // like a refused server: one is waited out, the other never resolves
      // itself and stops the reconnect ladder.
      final pinned = PinnedHttpClient()..pinTo(_fingerprint);
      final connection = WebSocketChannelFactory(pinned).connect(Uri.parse('wss://127.0.0.1:1/ws'));

      await expectLater(connection.frames.first, throwsA(isNot(isA<ServerPinRefusedException>())));
      expect(pinned.refusals, 0);
    });
  });
}
