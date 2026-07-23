import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/remote/api_client.dart';
import 'package:nox_app/data/remote/interceptor/auth_interceptor.dart';
import 'package:nox_app/domain/model/app_config/app_config.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
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
}

void main() {
  test('initBase with a null apiUrl leaves baseUrl empty but installs the AuthInterceptor (S5)', () {
    final client = ApiClient(_FakeConfig(null))..initBase();
    expect(client.dio.options.baseUrl, isEmpty); // inert — no real requests built
    expect(client.dio.interceptors.whereType<AuthInterceptor>().length, 1);
  });

  test('initBase sets the base URL from a non-empty apiUrl', () {
    final client = ApiClient(_FakeConfig('https://api.example.test'))..initBase();
    expect(client.dio.options.baseUrl, 'https://api.example.test');
    expect(client.dio.interceptors.whereType<AuthInterceptor>().length, 1);
  });

  test('initBase is idempotent — a second call does not double-install the interceptor', () {
    final client = ApiClient(_FakeConfig(null))
      ..initBase()
      ..initBase();
    expect(client.dio.interceptors.whereType<AuthInterceptor>().length, 1);
  });
}
