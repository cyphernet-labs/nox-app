import 'package:dio/dio.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';

/// Dio interceptor for the auth/transport seam (feature S5).
///
///  - [onRequest] attaches `Authorization: Bearer <token>` when a non-empty token is
///    available ([AppConfigRepository.getUserAuthIdToken]); anonymous (no header)
///    otherwise. The `Bearer` scheme is a placeholder: nothing writes the token yet.
///  - [onError] passes every error on, a 401 included. Since phase 044 a 401 from
///    `/files` is a failed transfer and nothing more: the connection proves this
///    device's key below HTTP, and the one owner of a forced logout is the session -
///    the server answering `session.hello` with `unauthenticated`, or this device
///    revoked from another (FR-013). A logout here would let any file answer wipe
///    the device.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._config);

  final AppConfigRepository _config;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _config.getUserAuthIdToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    handler.next(err); // always propagate — the interceptor never swallows the error
  }
}
