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

  /// The onion address and one-time private key a version-2 link lent this
  /// device for one pairing.
  static const String inviteOnion = 'session.invite_onion';
  static const String inviteAccessKey = 'session.invite_access_key';

  /// Private keys are kept out of any backup that could restore them on
  /// another device (FR-014): `this_device` items never migrate.
  static const IOSOptions keyIOSOptions = IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device);

  /// macOS keeps the legacy keychain the rest of the app uses (see
  /// RegisterModule): the data-protection keychain needs a signing setup the
  /// project does not have yet.
  static const MacOsOptions keyMacOsOptions = MacOsOptions(
    accessibility: KeychainAccessibility.unlocked_this_device,
    usesDataProtectionKeychain: false,
  );

  /// Deletes every record of this phase. [includeDeviceAccessKey] is false for
  /// a failed sign-in: the access key names this install, like the device key,
  /// and an attempt that never reached a server must not rotate it.
  static Future<void> delete(FlutterSecureStorage storage, {required bool includeDeviceAccessKey}) async {
    await storage.delete(key: serverAddresses);
    await storage.delete(key: accessKeyRegistered);
    await storage.delete(key: inviteOnion);
    await storage.delete(key: inviteAccessKey, iOptions: keyIOSOptions, mOptions: keyMacOsOptions);
    if (includeDeviceAccessKey) {
      await storage.delete(key: accessKey, iOptions: keyIOSOptions, mOptions: keyMacOsOptions);
    }
  }
}
