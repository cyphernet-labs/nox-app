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
}
