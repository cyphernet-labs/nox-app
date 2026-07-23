import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// DI module for third-party singletons used by the session/app-state spine.
/// `SharedPreferences` is `@preResolve`d (awaited during `getIt.allReady()`).
@module
abstract class RegisterModule {
  @lazySingleton
  FlutterSecureStorage get secureStorage => const FlutterSecureStorage(
    // macOS: use the LEGACY file-based keychain, not the data-protection keychain.
    // The data-protection keychain (flutter_secure_storage's macOS default) requires
    // the `keychain-access-groups` entitlement (Keychain Sharing) — which forces a
    // signed build with a real dev team; under the app sandbox WITHOUT it `SecItemAdd`
    // fails with errSecMissingEntitlement (-34018), so the first `signIn` keychain
    // write throws and the spine reports a (false) connection error. The legacy
    // keychain reaches the app's OWN items in the sandbox with no entitlement, so
    // local (ad-hoc-signed) and notarized builds both work. macOS-only knob — iOS /
    // Android / Windows (DPAPI) / Linux (libsecret) are unaffected.
    //
    // Constitution III reconciliation (009 plan): the planned macOS gate was "add
    // keychain-access-groups". That path needs signing infra NOT yet set up (no
    // backend / no release pipeline this phase) and broke `flutter run`, so the gate
    // is met instead by the sandbox's own per-app keychain isolation via the legacy
    // keychain — maintainer-approved 2026-06-26. Posture delta (legacy login keychain
    // vs data-protection) is acceptable while the stored value is a stub identifier;
    // revisit (switch to data-protection + the entitlement) when macOS signing lands.
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  @preResolve
  Future<SharedPreferences> get sharedPreferences => SharedPreferences.getInstance();

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
