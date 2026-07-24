import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/data/remote/interceptor/auth_interceptor.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_interceptor_test.mocks.dart';

@GenerateMocks([AppConfigRepository, AuthRepository])
void main() {
  // Mockito needs a dummy for the mock's return type (even when every call is stubbed).
  provideDummy<RepositoryResult<bool>>(const RepositoryResult<bool>.success(data: true));

  late MockAppConfigRepository config;

  setUp(() {
    config = MockAppConfigRepository();
  });

  group('onRequest attaches the bearer token (US2)', () {
    test('sets Authorization when a non-empty token is available', () async {
      when(config.getUserAuthIdToken()).thenAnswer((_) async => 'tok-123');
      final options = RequestOptions(path: '/x');

      final handler = _CapturingRequestHandler();
      await AuthInterceptor(config).onRequest(options, handler);

      expect(handler.captured!.headers['Authorization'], 'Bearer tok-123');
    });

    test('leaves headers untouched when the token is null (anonymous)', () async {
      when(config.getUserAuthIdToken()).thenAnswer((_) async => null);
      final options = RequestOptions(path: '/x');

      final handler = _CapturingRequestHandler();
      await AuthInterceptor(config).onRequest(options, handler);

      expect(handler.captured!.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('onError 401 → forced logout (US3)', () {
    late MockAuthRepository auth;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await configureDependencies(Environment.test);
      auth = MockAuthRepository();
      when(auth.logout(forced: anyNamed('forced'))).thenAnswer((_) async => const RepositoryResult<bool>.success(data: true));
      getIt.allowReassignment = true;
      getIt.registerSingleton<AuthRepository>(auth); // the lazy `authRepository` alias resolves to this
      addTearDown(() => getIt.allowReassignment = false);
    });

    tearDown(() async => getIt.reset());

    DioException dioError(int? status) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      response: status == null
          ? null
          : Response(
              requestOptions: RequestOptions(path: '/x'),
              statusCode: status,
            ),
    );

    test('a 401 response force-logs-out exactly once and propagates the error', () async {
      final handler = _CapturingErrorHandler();
      await AuthInterceptor(config).onError(dioError(401), handler);

      verify(auth.logout(forced: true)).called(1);
      expect(handler.propagated, isTrue);
    });

    test('a 500 response does not log out', () async {
      final handler = _CapturingErrorHandler();
      await AuthInterceptor(config).onError(dioError(500), handler);

      verifyNever(auth.logout(forced: anyNamed('forced')));
      expect(handler.propagated, isTrue);
    });

    test('an error with no response does not log out', () async {
      final handler = _CapturingErrorHandler();
      await AuthInterceptor(config).onError(dioError(null), handler);

      verifyNever(auth.logout(forced: anyNamed('forced')));
      expect(handler.propagated, isTrue);
    });
  });
}

/// Captures the options passed to `handler.next` without a real Dio dispatch.
class _CapturingRequestHandler extends RequestInterceptorHandler {
  RequestOptions? captured;

  @override
  void next(RequestOptions options) => captured = options;
}

/// Records that the error was propagated (next), without a real Dio dispatch.
class _CapturingErrorHandler extends ErrorInterceptorHandler {
  bool propagated = false;

  @override
  void next(DioException err) => propagated = true;
}
