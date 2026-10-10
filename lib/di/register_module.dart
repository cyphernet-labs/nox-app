import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/local/secure/secure_store_options.dart';
import 'package:nox_tor/channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// DI module for third-party singletons used by the session/app-state spine.
/// `SharedPreferences` is `@preResolve`d (awaited during `getIt.allReady()`).
@module
abstract class RegisterModule {
  /// The secure store, for this device only (phase 048): the options and why
  /// are [SecureStoreOptions].
  @lazySingleton
  FlutterSecureStorage get secureStorage =>
      const FlutterSecureStorage(iOptions: SecureStoreOptions.ios, mOptions: SecureStoreOptions.macOs);

  @preResolve
  Future<SharedPreferences> get sharedPreferences => SharedPreferences.getInstance();

  /// The secure channel of the native module (phase 044). Only the flavour
  /// that talks to a server opens one; constructing it loads nothing.
  @LazySingleton(env: [Environment.dev])
  NoxChannelApi get noxChannelApi => const NativeNoxChannelApi();

  // Env-keyed test-environment flag (feature S5) — true only under Environment.test.
  // Injected into AppConfigRepositoryImpl.isTestEnvironment (the future hook for
  // bypassing real auth in tests). The two getters cover disjoint environments.
  @test
  @Named('isTestEnvironment')
  bool get isTestEnvironmentUnderTest => true;

  @dev
  @prod
  @Named('isTestEnvironment')
  bool get isTestEnvironmentReal => false;
}
