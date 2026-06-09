import 'package:nox_app/domain/exception/base_repository_exception.dart';

/// General failure modes. Feature-specific exceptions implement the same
/// marker (BaseRepositoryException) as separate enums — there is NO typed
/// ApiException/DaoException hierarchy; data-layer errors are mapped into
/// this enum in BaseRepositoryHelper.execute.
enum RepositoryException implements BaseRepositoryException { unknown, internal, authentication, connection, unauthenticated, notFound }
