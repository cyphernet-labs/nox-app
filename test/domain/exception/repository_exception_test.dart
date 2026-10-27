import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';

void main() {
  group('RepositoryException.fromWireCode', () {
    test('maps every contract v0 wire code onto a distinct enum value', () {
      const expected = {
        'invalid_request': RepositoryException.invalidRequest,
        'not_found': RepositoryException.notFound,
        'name_taken': RepositoryException.nameTaken,
        'payload_too_large': RepositoryException.payloadTooLarge,
        'attachment_gone': RepositoryException.attachmentGone,
        'rate_limited': RepositoryException.rateLimited,
        'unauthenticated': RepositoryException.unauthenticated,
        'unsupported_schema': RepositoryException.unsupportedSchema,
        'internal': RepositoryException.internal,
      };
      expected.forEach((code, value) {
        expect(RepositoryException.fromWireCode(code), value, reason: code);
      });
      // Every mapped value is distinct — no two codes collapse together.
      expect(expected.values.toSet(), hasLength(expected.length));
    });

    test('an unknown code follows the evolution rule and becomes internal', () {
      expect(RepositoryException.fromWireCode('brand_new_code'), RepositoryException.internal);
      expect(RepositoryException.fromWireCode(''), RepositoryException.internal);
    });
  });
}
