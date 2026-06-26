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
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  @preResolve
  Future<SharedPreferences> get sharedPreferences => SharedPreferences.getInstance();
}
