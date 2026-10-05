import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/remote/api_client.dart';
import 'package:nox_app/data/remote/pinned_http_client.dart';
import 'package:nox_app/data/remote/interceptor/auth_interceptor.dart';
import 'package:nox_app/domain/model/app_config/app_config.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_app/domain/model/app_config/server_limits.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';

/// Minimal fake exposing a configurable apiUrl (the only thing initBase reads).
class _FakeConfig implements AppConfigRepository {
  _FakeConfig(this._apiUrl);
  final String? _apiUrl;

  @override
  AppConfig get config => AppConfig(flavor: AppFlavorType.stage, apiUrl: _apiUrl);
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

const String _fixtures = 'test/general/pairing/fixtures';

String get _fingerprint => File('$_fixtures/fingerprint.txt').readAsStringSync().trim();

/// The machine the pairing link named. [hold] keeps a request open until it
/// completes; everything else is answered at once.
Future<HttpServer> _honest({Completer<void>? hold}) async {
  final context = SecurityContext()
    ..useCertificateChainBytes(File('$_fixtures/valid.pem').readAsBytesSync())
    ..usePrivateKeyBytes(File('$_fixtures/server_key.pem').readAsBytesSync());
  final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
  server.listen((request) async {
    if (request.uri.path == '/held' && hold != null) await hold.future;
    request.response
      ..statusCode = HttpStatus.ok
      ..write('ok');
    await request.response.close();
  });
  return server;
}

void main() {
  test('an address with no scheme becomes https, never http', () {
    // The paired address is a bare host:port - that is what a pairing link
    // carries. Defaulting it to http is how the file half of the transport
    // stayed in the clear while the socket was already protected.
    final client = ApiClient(_FakeConfig(null), PinnedHttpClient())..initBase(address: '10.0.0.5:9000');
    expect(client.dio.options.baseUrl, 'https://10.0.0.5:9000');
    expect(client.dio.interceptors.whereType<AuthInterceptor>().length, 1);
  });

  test('a full URL is taken as given', () {
    final client = ApiClient(_FakeConfig(null), PinnedHttpClient())..initBase(address: 'https://api.example.test');
    expect(client.dio.options.baseUrl, 'https://api.example.test');
  });

  test('the build-time apiUrl is not a source of an address any more', () {
    // It names a machine nobody ever presented, so nothing can check the
    // connection to it. initBase used to fall back to it when called with
    // nothing; there is no such call now, and the parameter is required.
    final client = ApiClient(_FakeConfig('https://baked-into-the-build.test'), PinnedHttpClient())..initBase(address: '10.0.0.5:9000');
    expect(client.dio.options.baseUrl, 'https://10.0.0.5:9000');
  });

  test('bytes go through the pinned client, not through a client of Dio own making', () {
    // Without this adapter the file half opens its own connections, and the
    // certificate of the machine they reach is checked by nothing.
    final client = ApiClient(_FakeConfig(null), PinnedHttpClient())..initBase(address: '10.0.0.5:9000');
    expect(client.dio.httpClientAdapter, isA<IOHttpClientAdapter>());
  });

  test('initBase is idempotent - a second call does not double-install the interceptor', () {
    final client = ApiClient(_FakeConfig(null), PinnedHttpClient())
      ..initBase(address: '10.0.0.5:9000')
      ..initBase(address: '10.0.0.5:9000');
    expect(client.dio.interceptors.whereType<AuthInterceptor>().length, 1);
  });

  test('one client serves both transports, so there is one pin and one TLS session', () {
    final pinned = PinnedHttpClient();
    final first = pinned.client;
    expect(identical(pinned.client, first), isTrue, reason: 'a client per use would leak one on every reconnect');
  });

  group('the transfer generation (phase 043)', () {
    late HttpOverrides? saved;
    setUpAll(() {
      saved = HttpOverrides.current;
      HttpOverrides.global = null;
    });
    tearDownAll(() => HttpOverrides.global = saved);

    test('cancelTransfers ends a transfer under way, and the next one goes through', () async {
      // A logout or a change of server must not leave bytes moving towards a
      // machine nobody uses any more.
      final hold = Completer<void>();
      final server = await _honest(hold: hold);
      addTearDown(() async {
        if (!hold.isCompleted) hold.complete();
        await server.close(force: true);
      });
      final api = ApiClient(_FakeConfig(null), PinnedHttpClient()..pinTo(_fingerprint))
        ..initBase(address: 'https://127.0.0.1:${server.port}');

      final token = api.beginTransfer();
      final held = api.dio.get<String>('/held', cancelToken: token);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      api.cancelTransfers();

      await expectLater(held, throwsA(isA<DioException>().having((e) => e.type, 'type', DioExceptionType.cancel)));

      final next = api.beginTransfer();
      final response = await api.dio.get<String>('/anything', cancelToken: next);
      api.endTransfer(next);
      expect(response.statusCode, HttpStatus.ok);
      expect(next.isCancelled, isFalse, reason: 'a transfer begun after the cancel is not touched by it');
    });

    test('a finished transfer is forgotten: a later cancel does not reach it', () {
      final api = ApiClient(_FakeConfig(null), PinnedHttpClient());
      final done = api.beginTransfer();
      api.endTransfer(done);

      api.cancelTransfers();

      expect(done.isCancelled, isFalse);
    });
  });
}
