import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/exception/base_repository_exception.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';

void main() {
  group('RepositoryResultMatch.match on a success result', () {
    const success = RepositoryResult<int>.success(data: 42);

    test('calls onData with the exact data and never onError', () {
      int? seenData;
      var onErrorCalled = false;

      success.match(onData: (data) => seenData = data, onError: (_) => onErrorCalled = true);

      expect(seenData, 42);
      expect(onErrorCalled, isFalse);
    });

    test('returns the value produced by the onData branch', () {
      final result = success.match(onData: (data) => 'data:$data', onError: (_) => 'error');

      expect(result, 'data:42');
    });
  });

  group('RepositoryResultMatch.match on an error result', () {
    const RepositoryResult<int> error = RepositoryResult<int>.error(exception: RepositoryException.unknown);

    test('calls onError with the exact exception and never onData', () {
      BaseRepositoryException? seenException;
      var onDataCalled = false;

      error.match(onData: (_) => onDataCalled = true, onError: (exception) => seenException = exception);

      expect(seenException, same(RepositoryException.unknown));
      expect(onDataCalled, isFalse);
    });

    test('returns the value produced by the onError branch', () {
      final result = error.match(onData: (data) => 'data:$data', onError: (exception) => 'error:$exception');

      expect(result, 'error:${RepositoryException.unknown}');
    });
  });
}
