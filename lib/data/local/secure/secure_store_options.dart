import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The options of the secure store, for this device only (phase 048, FR-001 -
/// FR-003): no record of it may reach a backup or another device.
///
/// - **iOS** - `first_unlock_this_device`: readable from the first unlock
///   after a restart, never carried to another phone by a backup.
/// - **macOS** - the data-protection keychain with the same class. The legacy
///   file keychain goes into Time Machine, and Migration Assistant carries it
///   to the next Mac; the data-protection one needs the
///   `keychain-access-groups` entitlement, so the macOS build is signed by the
///   team (CI builds it unsigned: it never runs there).
/// - **Android** - the plugin's store, under a key of the Android Keystore that
///   never leaves the device; the manifest keeps the store out of backups and
///   device-to-device transfer.
/// - **Windows** - DPAPI for the current user; the plugin's file lives in the
///   local application data, which a roaming profile does not carry
///   (`AppDataRoot.useLocalFolderOnWindows`).
/// - **Linux** - libsecret: the local keyring, synced by nothing.
abstract final class SecureStoreOptions {
  const SecureStoreOptions._();

  /// The keychain service every record lives under on iOS and macOS. Not the
  /// plugin's default: the records builds before this phase wrote stay under
  /// that one, where the start-up sweep finds them and nothing else.
  static const String keychainService = 'com.cyphernetlabs.noxapp';

  static const IOSOptions ios = IOSOptions(accountName: keychainService, accessibility: KeychainAccessibility.first_unlock_this_device);

  static const MacOsOptions macOs = MacOsOptions(
    accountName: keychainService,
    accessibility: KeychainAccessibility.first_unlock_this_device,
    usesDataProtectionKeychain: true,
  );
}
