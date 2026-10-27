import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nox_app/data/local/secure/secure_storage_delete.dart';

/// The secure-storage records of the connection settings, and the options the
/// records of earlier builds were written with, in one place: a wipe must
/// delete each BY NAME and with the SAME options, or a record written under
/// options the delete query does not match survives it silently.
abstract final class ConnectionStorage {
  const ConnectionStorage._();

  /// JSON - where the server said it can be reached, what the person changed
  /// by hand, and whether Tor may be used (phase 045).
  static const String serverAddresses = 'session.server_addresses';

  /// base64 of the x25519 private access key builds of phases 040-044 kept
  /// for the onion service. Nothing reads it since phase 045 - the onion
  /// address is open to whoever knows it, and the channel's check of the
  /// server key is what lets anyone further - so it is swept at every launch.
  static const String legacyAccessKey = 'session.access_key';

  /// `1` once the server had accepted the key above; swept with it.
  static const String legacyAccessKeyRegistered = 'session.access_key_registered';

  /// The options the access key above was written with: `this_device` items
  /// never migrate to another phone through a backup. A delete under other
  /// options would not match it.
  static const IOSOptions legacyKeyIOSOptions = IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device);

  /// macOS keeps the legacy keychain the rest of the app uses (see
  /// RegisterModule); it has no `this_device` class, so the attribute was
  /// ignored there, and the delete names the keychain the same way.
  static const MacOsOptions legacyKeyMacOsOptions = MacOsOptions(usesDataProtectionKeychain: false);

  /// Deletes the connection settings: a logout, a failed sign-in, a new
  /// server.
  static Future<void> delete(FlutterSecureStorage storage) => storage.deleteIfPresent(key: serverAddresses);

  /// Deletes what earlier builds kept and nothing reads any more - each with
  /// the options it was written under.
  static Future<void> sweepLegacy(FlutterSecureStorage storage) async {
    await storage.deleteIfPresent(key: legacyAccessKeyRegistered);
    await storage.deleteIfPresent(key: legacyAccessKey, iOptions: legacyKeyIOSOptions, mOptions: legacyKeyMacOsOptions);
  }
}
