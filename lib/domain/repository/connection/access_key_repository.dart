import 'dart:convert';
import 'dart:typed_data';

import 'package:nox_app/domain/repository/base/repository_result.dart';

/// An x25519 key pair for the server's onion service.
class AccessKeyPair {
  const AccessKeyPair({required this.privateKey, required this.publicKey});

  final Uint8List privateKey;
  final Uint8List publicKey;

  /// Standard base64 of the public half - what the wire carries (`access_key`).
  String get publicBase64 => base64Encode(publicKey);
}

/// This device's onion access key (phase 040, until phase 045 retires access
/// keys). The private half never leaves the device: no sync, no backup, wiped
/// with the session. It is the only one: pairing links carry no one-time key
/// any more (phase 044).
abstract class AccessKeyRepository {
  /// The device's key, created on first use.
  Future<RepositoryResult<AccessKeyPair>> deviceKey();

  /// The device's key if one exists; never creates one. For the readers that
  /// only USE the key: a key minted where only a registered one would do is
  /// not registered anywhere, and minted during a logout it would survive it.
  Future<RepositoryResult<AccessKeyPair?>> storedDeviceKey();

  /// Replaces the device's key with a fresh one - the server refused the old.
  Future<RepositoryResult<AccessKeyPair>> regenerate();

  Future<RepositoryResult<bool>> isRegistered();

  Future<RepositoryResult<bool>> markRegistered(bool registered);
}
