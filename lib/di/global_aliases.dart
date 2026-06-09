import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/item/item_repository.dart';
import 'package:nox_app/domain/repository/log_repository.dart';

/// Convenience getters over the DI container.
/// Cross-cutting
LogRepository get logRepository => getIt<LogRepository>();

/// Repositories
ItemRepository get itemRepository => getIt<ItemRepository>();
