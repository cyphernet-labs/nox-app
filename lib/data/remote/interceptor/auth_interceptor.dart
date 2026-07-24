import 'package:dio/dio.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';

/// Dio interceptor for the auth/transport seam (feature S5). Two behaviors:
///  - [onRequest] attaches `Authorization: Bearer <token>` when a non-empty token is
///    available ([AppConfigRepository.getUserAuthIdToken]); anonymous (no header) otherwise.
///  - [onError] on a 401 response force-logs-out ([AuthRepository.logout] with `forced:true`),
///    reusing the existing forced-logout path (spine → `sessionExpired` → Login).
///
/// [AuthRepository] is resolved LAZILY at 401 time (via the `authRepository` top-level
/// alias), never held as a constructor reference — this breaks any potential
/// `ApiClient → AuthInterceptor → AuthRepository → repositories` DI cycle. The
/// `Bearer` scheme is an example/TBD placeholder until the NOX backend is chosen.
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
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    // A 401 means the token is no longer valid → force a full logout (the spine returns
    // to Login via the one-shot sessionExpired flag). Lazy AuthRepository resolution.
    if (err.response?.statusCode == 401) {
      await authRepository.logout(forced: true);
    }
    handler.next(err); // always propagate — the interceptor never swallows the error
  }
}
