import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The secure-storage records of phase 040 and the options they are written
/// with, in one place: the session wipe must delete each BY NAME and with the
/// SAME options, or a record written under options the delete query does not
/// match survives it silently.
abstract final class ConnectionStorage {
  const ConnectionStorage._();

  /// JSON `{direct, onion, last_good}` - where the server said it can be reached.
  static const String serverAddresses = 'session.server_addresses';

  /// base64 of this device's x25519 private access key.
  static const String accessKey = 'session.access_key';

  /// `1` once the server accepted the key above.
  static const String accessKeyRegistered = 'session.access_key_registered';

  /// The private key is kept out of any backup that could restore it on
  /// another phone (FR-014): `this_device` items never migrate.
  static const IOSOptions keyIOSOptions = IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device);

  /// macOS keeps the legacy keychain the rest of the app uses (see
  /// RegisterModule): the data-protection keychain needs a signing setup the
  /// project does not have yet. That keychain has no `this_device` class - it
  /// ignores the attribute - so nothing is claimed here: the key lives in the
  /// login keychain like the device key does, never synced to iCloud, and a
  /// whole-machine migration carries both together, which the server sees as
  /// the same device moving.
  static const MacOsOptions keyMacOsOptions = MacOsOptions(usesDataProtectionKeychain: false);

  /// Deletes every record of this phase. [includeDeviceAccessKey] is false for
  /// a failed sign-in: the access key names this install, like the device key,
  /// and an attempt that never reached a server must not rotate it.
  static Future<void> delete(FlutterSecureStorage storage, {required bool includeDeviceAccessKey}) async {
    await storage.delete(key: serverAddresses);
    await storage.delete(key: accessKeyRegistered);
    if (includeDeviceAccessKey) {
      await storage.delete(key: accessKey, iOptions: keyIOSOptions, mOptions: keyMacOsOptions);
    }
  }
}
