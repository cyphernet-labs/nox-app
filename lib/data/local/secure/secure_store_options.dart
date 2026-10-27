import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The options of the secure store, for this device only (phase 048, FR-001 -
/// FR-003): no record of it may reach a backup or another device.
///
/// - **iOS** - `first_unlock_this_device`: readable from the first unlock
///   after a restart, never carried to another phone by a backup.
/// - **macOS** - a release build keeps its records in the data-protection
///   keychain with the same class. The legacy file keychain goes into Time
///   Machine, and Migration Assistant carries it to the next Mac; the
///   data-protection one needs the `keychain-access-groups` entitlement
///   (`Release.entitlements`), which only a build signed by a team may carry.
///   A debug or profile build is signed to run locally, with no team, so it
///   keeps its records in the login keychain: they do reach Time Machine,
///   which a developer's own Mac accepts and a release never does.
/// - **Android** - the plugin's store, under a key of the Android Keystore that
///   never leaves the device; the manifest keeps the store out of backups and
///   device-to-device transfer. A store the Keystore cannot decrypt is an
///   error, not an empty store the plugin made by deleting it ([android]).
/// - **Windows** - the plugin deletes its file when DPAPI cannot decrypt it,
///   and there is no option against that: a lasting DPAPI failure costs the
///   local data and a pairing there, like a key that is gone.
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

  /// macOS, a release build: the data-protection keychain.
  @visibleForTesting
  static const MacOsOptions macOsRelease = MacOsOptions(
    accountName: keychainService,
    accessibility: KeychainAccessibility.first_unlock_this_device,
    usesDataProtectionKeychain: true,
  );

  /// macOS, a debug or profile build: the login keychain, which asks for no
  /// entitlement.
  @visibleForTesting
  static const MacOsOptions macOsLocal = MacOsOptions(
    accountName: keychainService,
    accessibility: KeychainAccessibility.first_unlock_this_device,
    usesDataProtectionKeychain: false,
  );

  static const MacOsOptions macOs = kReleaseMode ? macOsRelease : macOsLocal;

  /// Android: a read the Keystore fails is an error that reaches the app. By
  /// default the plugin answers it by deleting the record - or the whole
  /// store - and reading nothing, so a Keystore failing for a moment after an
  /// update read as a key that is gone, and the start wiped the local data
  /// and the pairing (048, FR-011). The app decides instead
  /// (`AuthRepositoryImpl.unreadableLimit`).
  static const AndroidOptions android = AndroidOptions(resetOnError: false);
}
