import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.config.dart';

final getIt = GetIt.instance;

/// Single DI entry point for the whole package. `env` selects the registration
/// environment (Environment.dev / .prod / .test).
@InjectableInit(initializerName: r'$initGetIt')
Future<void> configureDependencies(String env) async {
  // Awaited: with a `@preResolve` dependency (SharedPreferences) the generated
  // `$initGetIt` is async, so registration only completes once it is awaited.
  await getIt.$initGetIt(environment: env);
}
