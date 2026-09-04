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

  /// Idempotent for the interceptor; the base URL is re-pointed on every call.
  ///
  /// [address] wins when given: since pairing, the server is the one from the
  /// link, and file bytes have to go to the SAME machine the socket talks to.
  /// Leaving them on the build-time address would upload an attachment to one
  /// server and reference it from a message on another, where the id resolves
  /// to nothing.
  void initBase({String? address}) {
    final apiUrl = address ?? _config.config.apiUrl;
    if (apiUrl != null && apiUrl.isNotEmpty) {
      dio.options.baseUrl = apiUrl.contains('://') ? apiUrl : 'http://$apiUrl';
    }
    if (dio.interceptors.whereType<AuthInterceptor>().isEmpty) {
      dio.interceptors.add(AuthInterceptor(_config));
    }
  }
}
