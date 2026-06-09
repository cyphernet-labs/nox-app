import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/exception/base_repository_exception.dart';

part 'repository_result.freezed.dart';

/// data XOR exception — exactly one present. Only `.freezed.dart` (not serialized).
@freezed
sealed class RepositoryResult<T> with _$RepositoryResult<T> {
  const RepositoryResult._();

  const factory RepositoryResult.success({required T data}) = RepositoryResultSuccess<T>;

  const factory RepositoryResult.error({required BaseRepositoryException exception}) = RepositoryResultError<T>;

  bool get hasData => this is RepositoryResultSuccess<T>;

  /// Non-null data on a success result; null on error. Prefer [match].
  T? get data => switch (this) {
    RepositoryResultSuccess(:final data) => data,
    _ => null,
  };

  /// The exception on an error result; null on success.
  BaseRepositoryException? get exception => switch (this) {
    RepositoryResultError(:final exception) => exception,
    _ => null,
  };
}
