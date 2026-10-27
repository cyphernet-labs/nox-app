import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

void main() {
  group('RepositoryResult.success', () {
    const result = RepositoryResult<int>.success(data: 42);

    test('is a RepositoryResultSuccess', () {
      expect(result, isA<RepositoryResultSuccess<int>>());
    });

    test('reports hasData true', () {
      expect(result.hasData, isTrue);
    });

    test('exposes the wrapped data', () {
      expect(result.data, 42);
    });

    test('carries no exception', () {
      expect(result.exception, isNull);
    });
  });

  group('RepositoryResult.error', () {
    const result = RepositoryResult<int>.error(exception: RepositoryException.unknown);

    test('is a RepositoryResultError', () {
      expect(result, isA<RepositoryResultError<int>>());
    });

    test('reports hasData false', () {
      expect(result.hasData, isFalse);
    });

    test('exposes null data', () {
      expect(result.data, isNull);
    });

    test('carries the wrapped exception', () {
      expect(result.exception, RepositoryException.unknown);
    });
  });
}
