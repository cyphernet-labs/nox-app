import 'package:dio/dio.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/exception/base_repository_exception.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

/// Wraps a repository operation in try/catch, ALWAYS logs via LogRepository,
/// and coarsely maps framework errors to a domain RepositoryException.
/// Exactly two catch branches; no typed Dao/ApiException hierarchy.
mixin BaseRepositoryHelper {
  Future<RepositoryResult<TD>> execute<TD>(Function executionFunction) async {
    try {
      return await executionFunction();
    } on BaseRepositoryException catch (e, stackTrace) {
      // An already-mapped domain failure (e.g. a wire error code from
      // unwrapEnvelope) passes through undiluted - never downgraded to
      // `unknown` by the catch-all.
      logRepository.error(target: this, error: e, stackTrace: stackTrace);
      return RepositoryResult<TD>.error(exception: e);
    } on DioException catch (e, stackTrace) {
      logRepository.error(target: this, error: e, stackTrace: stackTrace);
      return RepositoryResult<TD>.error(exception: _mapDioException(e));
    } catch (e, stackTrace) {
      logRepository.error(target: this, error: e, stackTrace: stackTrace);
      return RepositoryResult<TD>.error(exception: RepositoryException.unknown);
    }
  }

  /// Unwraps a data-source envelope: the payload when present, otherwise the
  /// contract §2.1 error code mapped onto [RepositoryException] (an unknown
  /// code degrades to `internal` per the evolution rule), otherwise a bare
  /// StateError (malformed envelope) that the catch-all maps to `unknown`.
  TD unwrapEnvelope<TD>(ResponseEntity<TD> response, String what) {
    final data = response.data;
    if (data != null) return data;
    final error = response.error;
    if (error != null) throw RepositoryException.fromWireCode(error.code);
    throw StateError('$what envelope has no data (success=${response.success})');
  }

  /// Maps a transport error to a domain [RepositoryException] by connection type and
  /// HTTP status. Enables error/offline/notFound BLoC states to be driven through the
  /// real path once the backend lands (mock APIs never throw these today).
  RepositoryException _mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return RepositoryException.connection;
      case DioExceptionType.badResponse:
        switch (e.response?.statusCode) {
          case 401:
            return RepositoryException.unauthenticated;
          case 403:
            return RepositoryException.authentication;
          case 404:
            return RepositoryException.notFound;
          default:
            return RepositoryException.internal;
        }
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return RepositoryException.internal;
    }
  }
}
