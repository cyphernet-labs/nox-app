import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';

/// Flavor-dependent runtime config. Skeleton carries only the flavor; the
/// token source / apiUrl / security headers are example/TBD (backend not chosen).
class AppConfig {
  const AppConfig({required this.flavor});

  final AppFlavorType flavor;
}
