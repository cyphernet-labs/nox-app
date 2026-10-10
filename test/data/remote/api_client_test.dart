import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/remote/api_client.dart';
import 'package:nox_app/data/remote/channel/channel_http_client.dart';
import 'package:nox_app/data/remote/interceptor/auth_interceptor.dart';
import 'package:nox_app/data/repository/log_repository_impl.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/app_config/app_config.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_app/domain/model/app_config/server_limits.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/log_repository.dart';

import 'channel/fake_channel.dart';

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

final Uint8List _serverKey = Uint8List.fromList(List<int>.generate(32, (i) => 0xA0 + i));
final Uint8List _deviceSeed = Uint8List.fromList(List<int>.generate(32, (i) => i));

/// A channel client bound to the server, with its channels opened to [port]
/// on loopback - the server under test stands in for the one at any address.
ChannelHttpClient _channels({int port = 1}) =>
    ChannelHttpClient(LoopbackChannelApi(port))..bind(serverKey: _serverKey, deviceSeed: _deviceSeed);

/// The machine the pairing link named. [hold] keeps a request open until it
/// completes; everything else is answered at once. Plain HTTP: the channel
/// below `HttpClient` is the module's, and the loopback one carries bytes as
/// they are.
Future<HttpServer> _honest({Completer<void>? hold}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
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
  setUp(() {
    getIt.allowReassignment = true;
    getIt.registerSingleton<LogRepository>(LoggerLogRepository());
  });
  tearDown(getIt.reset);

  test('an address with no scheme becomes https, never http', () {
    // The paired address is a bare host:port - that is what a pairing link
    // carries. Defaulting it to http is how the file half of the transport
    // stayed in the clear while the socket was already protected.
    final client = ApiClient(_FakeConfig(null), _channels())..initBase(address: '10.0.0.5:9000');
    expect(client.dio.options.baseUrl, 'https://10.0.0.5:9000');
    expect(client.dio.interceptors.whereType<AuthInterceptor>().length, 1);
  });

  test('a full URL is taken as given', () {
    final client = ApiClient(_FakeConfig(null), _channels())..initBase(address: 'https://api.example.test');
    expect(client.dio.options.baseUrl, 'https://api.example.test');
  });

  test('the build-time apiUrl is not a source of an address any more', () {
    // It names a machine nobody ever presented, so nothing can check the
    // connection to it. initBase used to fall back to it when called with
    // nothing; there is no such call now, and the parameter is required.
    final client = ApiClient(_FakeConfig('https://baked-into-the-build.test'), _channels())..initBase(address: '10.0.0.5:9000');
    expect(client.dio.options.baseUrl, 'https://10.0.0.5:9000');
  });

  test('bytes go through the channel client, not through a client of Dio own making', () {
    // Without this adapter the file half opens its own connections, past the
    // channel - and nothing checks which machine they reach.
    final client = ApiClient(_FakeConfig(null), _channels())..initBase(address: '10.0.0.5:9000');
    expect(client.dio.httpClientAdapter, isA<IOHttpClientAdapter>());
  });

  test('initBase is idempotent - a second call does not double-install the interceptor', () {
    final client = ApiClient(_FakeConfig(null), _channels())
      ..initBase(address: '10.0.0.5:9000')
      ..initBase(address: '10.0.0.5:9000');
    expect(client.dio.interceptors.whereType<AuthInterceptor>().length, 1);
  });

  test('each transport keeps one client of its own for the process, and a new binding replaces both', () {
    final channels = _channels();
    final socket = channels.client;
    final bytes = channels.transferClient;
    expect(identical(channels.client, socket), isTrue, reason: 'a client per use would leak one on every reconnect');
    expect(identical(channels.transferClient, bytes), isTrue);
    expect(identical(socket, bytes), isFalse, reason: 'what Dio sets on its client must not reach the socket');

    channels.bind(serverKey: Uint8List(32), deviceSeed: _deviceSeed);

    expect(identical(channels.client, socket), isFalse, reason: 'a connection to the old machine is never checked again');
    expect(identical(channels.transferClient, bytes), isFalse);
  });

  test('a new binding re-installs the adapter, so Dio does not keep the client that was thrown away', () {
    final channels = _channels();
    final api = ApiClient(_FakeConfig(null), channels)..initBase(address: '10.0.0.5:9000');
    final before = api.dio.httpClientAdapter;

    channels.bind(serverKey: Uint8List(32), deviceSeed: _deviceSeed);

    expect(identical(api.dio.httpClientAdapter, before), isFalse);
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
      final api = ApiClient(_FakeConfig(null), _channels(port: server.port))..initBase(address: 'https://192.168.1.20:8443');

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
      final api = ApiClient(_FakeConfig(null), _channels());
      final done = api.beginTransfer();
      api.endTransfer(done);

      api.cancelTransfers();

      expect(done.isCancelled, isFalse);
    });
  });

  group('the socket and the transfers apart (phase 043)', () {
    late HttpOverrides? saved;
    setUpAll(() {
      saved = HttpOverrides.current;
      HttpOverrides.global = null;
    });
    tearDownAll(() => HttpOverrides.global = saved);

    test('a transfer leaves the socket its own connect budget', () async {
      // Dio writes its connect timeout onto the client it is given, on every
      // request, and the socket dials through that same setting: one transfer
      // at home cut the socket's next dial through Tor at Dio's 30 s instead
      // of its own 45.
      final server = await _honest();
      addTearDown(() => server.close(force: true));
      final channels = _channels(port: server.port);
      final api = ApiClient(_FakeConfig(null), channels)..initBase(address: 'https://192.168.1.20:8443');

      final response = await api.dio.get<String>('/anything');

      expect(response.statusCode, HttpStatus.ok);
      expect(channels.client.connectionTimeout, isNull, reason: 'the socket bounds its own dial');
      expect(channels.transferClient.connectionTimeout, api.dio.options.connectTimeout, reason: 'it went by the transfers\' client');
    });
  });

  group('a change of path (phase 043, FR-008)', () {
    test('a new address ends the transfers on the old one', () {
      final api = ApiClient(_FakeConfig(null), _channels())..initBase(address: '10.0.0.5:9000');
      final under = api.beginTransfer();

      final before = api.pathGeneration;

      api.initBase(address: 'abcdefghijklmnopqrstuvwxyz234567abcdefghijklmnopqrstuvwx.onion:443');

      expect(under.isCancelled, isTrue, reason: 'it continues on the new path at once, not after the stall limit');
      expect(api.pathGeneration, before + 1, reason: 'so the transfer it ended can tell why');
    });

    test('the same address ends nothing - a transfer on a path still in use goes on', () {
      final api = ApiClient(_FakeConfig(null), _channels())..initBase(address: '10.0.0.5:9000');
      final under = api.beginTransfer();

      final before = api.pathGeneration;

      api.initBase(address: '10.0.0.5:9000');
      api.initBase(address: 'https://10.0.0.5:9000');

      expect(under.isCancelled, isFalse);
      expect(api.pathGeneration, before);
    });

    test('the first address ends nothing', () {
      final api = ApiClient(_FakeConfig(null), _channels());
      final under = api.beginTransfer();

      api.initBase(address: '10.0.0.5:9000');

      expect(under.isCancelled, isFalse);
    });
  });
}
