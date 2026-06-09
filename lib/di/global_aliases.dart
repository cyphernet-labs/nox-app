import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/log_repository.dart';

/// Convenience getters over the DI container.
/// Cross-cutting
LogRepository get logRepository => getIt<LogRepository>();

// Feature repositories (e.g. itemRepository) are added with their feature (US2).
