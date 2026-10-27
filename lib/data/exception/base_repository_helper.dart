import 'package:dio/dio.dart';
import 'package:nox_app/data/remote/socket/socket_channel_factory.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/exception/base_repository_exception.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

/// Wraps a repository operation in try/catch, ALWAYS logs via LogRepository,
/// and coarsely maps framework errors to a domain RepositoryException.
///
/// FOUR catch branches, in this order, and the order is the point: an
/// already-mapped domain error passes through undiluted, a dead socket becomes
/// `connection` (or every cache fallback guarded on it is unreachable), a Dio
/// error maps by type/status, and the catch-all degrades to `unknown`. No typed
/// Dao/ApiException hierarchy.
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
    } on SocketUnavailableException catch (e, stackTrace) {
      // The live channel is down, or a command went unanswered. Without this
      // branch it lands in the catch-all as `unknown`, and every cache fallback
      // guarded on `connection` becomes unreachable code.
      logRepository.error(target: this, error: e, stackTrace: stackTrace);
      return RepositoryResult<TD>.error(exception: RepositoryException.connection);
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
  /// HTTP status — the HTTP path (blob upload/download, phase 028). Envelope errors
  /// take the other route: [unwrapEnvelope] throws the code-mapped exception and the
  /// `on BaseRepositoryException` branch re-emits it unchanged.
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
