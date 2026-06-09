import 'package:nox_app/domain/exception/base_repository_exception.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

/// Canonical way to consume a result — exactly two branches (data XOR error).
extension RepositoryResultMatch<T> on RepositoryResult<T> {
  R match<R>({
    required R Function(T data) onData,
    required R Function(BaseRepositoryException exception) onError,
  }) =>
      switch (this) {
        RepositoryResultSuccess(:final data) => onData(data),
        RepositoryResultError(:final exception) => onError(exception),
      };
}
