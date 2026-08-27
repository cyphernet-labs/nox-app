import 'package:nox_app/domain/exception/base_repository_exception.dart';

/// General failure modes. Feature-specific exceptions implement the same
/// marker (BaseRepositoryException) as separate enums — there is NO typed
/// ApiException/DaoException hierarchy; data-layer errors are mapped into
/// this enum in BaseRepositoryHelper.execute.
///
/// The wire values mirror contract v0 §2.1 error codes so command failures
/// stay distinguishable end to end (invalid_request, name_taken,
/// payload_too_large, attachment_gone, rate_limited, unsupported_schema).
enum RepositoryException implements BaseRepositoryException {
  unknown,
  internal,
  authentication,
  connection,
  unauthenticated,
  notFound,
  invalidRequest,
  nameTaken,
  payloadTooLarge,
  attachmentGone,
  rateLimited,
  unsupportedSchema;

  /// Maps a contract §2.1 wire error code onto an enum value. The evolution
  /// rule applies: a code unknown to this client build is treated as
  /// [internal] (inline retry), never as a crash.
  static RepositoryException fromWireCode(String code) => switch (code) {
    'invalid_request' => invalidRequest,
    'not_found' => notFound,
    'name_taken' => nameTaken,
    'payload_too_large' => payloadTooLarge,
    'attachment_gone' => attachmentGone,
    'rate_limited' => rateLimited,
    'unauthenticated' => unauthenticated,
    'unsupported_schema' => unsupportedSchema,
    'internal' => internal,
    _ => internal,
  };
}
