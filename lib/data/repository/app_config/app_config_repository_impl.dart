import 'package:injectable/injectable.dart';
import 'package:nox_app/domain/model/app_config/app_config.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';

@LazySingleton(as: AppConfigRepository, env: [Environment.dev, Environment.prod, Environment.test])
class AppConfigRepositoryImpl implements AppConfigRepository {
  AppConfig? _config;

  @override
  Future<void> initialize({required AppFlavorType flavorType}) async {
    // Skeleton: config carries only the flavor. Token source / apiUrl / security
    // headers bootstrap is example/TBD (backend not chosen).
    _config = AppConfig(flavor: flavorType);
  }

  @override
  AppConfig get config => _config ?? (throw StateError('AppConfigRepository.initialize was not called'));
}
