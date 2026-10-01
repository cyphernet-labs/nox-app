import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Deleting a secure-storage record that may not be there.
extension SecureStorageDelete on FlutterSecureStorage {
  /// Deletes [key] only when it is there.
  ///
  /// On macOS the plugin deletes in two variants, synchronizable and not, and
  /// the legacy keychain this app uses refuses the synchronizable one from an
  /// app without the iCloud keychain entitlement (-34018). For a record that
  /// exists the other variant succeeds and so does the call; for one that does
  /// not, the refusal is what comes back. A sign-in, a rollback or a logout
  /// clearing a record it never wrote failed on it.
  Future<void> deleteIfPresent({required String key, IOSOptions? iOptions, MacOsOptions? mOptions}) async {
    if (!await containsKey(key: key, iOptions: iOptions, mOptions: mOptions)) return;
    await delete(key: key, iOptions: iOptions, mOptions: mOptions);
  }
}
