import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';

/// Flavor-dependent runtime config: the flavor, and nothing else. A server
/// address never comes from the build - it comes from the pairing link, which
/// also names the key the server has to prove (contract §8A).
class AppConfig {
  const AppConfig({required this.flavor});

  final AppFlavorType flavor;
}
