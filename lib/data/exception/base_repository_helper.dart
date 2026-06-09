import 'package:dio/dio.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

/// Wraps a repository operation in try/catch, ALWAYS logs via LogRepository,
/// and coarsely maps framework errors to a domain RepositoryException.
/// Exactly two catch branches; no typed Dao/ApiException hierarchy.
mixin BaseRepositoryHelper {
  Future<RepositoryResult<TD>> execute<TD>(Function executionFunction) async {
    try {
      return await executionFunction();
    } on DioException catch (e, stackTrace) {
      logRepository.error(target: this, error: e, stackTrace: stackTrace);
      return RepositoryResult<TD>.error(exception: RepositoryException.internal);
    } catch (e, stackTrace) {
      logRepository.error(target: this, error: e, stackTrace: stackTrace);
      return RepositoryResult<TD>.error(exception: RepositoryException.unknown);
    }
  }
}
