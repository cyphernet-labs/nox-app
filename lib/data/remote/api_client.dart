import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/remote/interceptor/auth_interceptor.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';

/// Thin Dio wrapper. [initBase] configures the base URL from [AppConfig.apiUrl] and
/// installs the [AuthInterceptor] (feature S5).
///
/// Inert for COMMANDS, and permanently so: contract v0 carries them over the
/// WebSocket envelope (feature 026), never over HTTP. REST exists only for blob
/// upload/download, so nothing calls [initBase] from app code and no data source
/// injects this client — that binding arrives with the file chain (phase 028).
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
