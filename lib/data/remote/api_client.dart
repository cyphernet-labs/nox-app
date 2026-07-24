import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/remote/interceptor/auth_interceptor.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';

/// Thin Dio wrapper. [initBase] configures the base URL from [AppConfig.apiUrl] and
/// installs the [AuthInterceptor] (feature S5). Inert while `apiUrl` is null (TBD —
/// backend/protocol not chosen): no base URL is set, so no real requests are built,
/// though the interceptor is installed and ready. Not yet injected into the data
/// sources (the mocks don't use it) — that binding lands with the backend.
/// HMAC/security headers stay example/TBD (see blueprint 14-networking-and-auth.md).
@lazySingleton
class ApiClient {
  ApiClient(this._config)
    : dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 30), receiveTimeout: const Duration(seconds: 30)));

  final AppConfigRepository _config;
  final Dio dio;

  /// Idempotent: sets the base URL (when `apiUrl` is non-empty) and installs the auth
  /// interceptor exactly once (a second call is a no-op).
  void initBase() {
    final apiUrl = _config.config.apiUrl;
    if (apiUrl != null && apiUrl.isNotEmpty) {
      dio.options.baseUrl = apiUrl;
    }
    if (dio.interceptors.whereType<AuthInterceptor>().isEmpty) {
      dio.interceptors.add(AuthInterceptor(_config));
    }
  }
}
