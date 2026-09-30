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

/// This device's onion access key, and the one-time key an invite link may
/// carry (phase 040). The private halves never leave the device: no sync, no
/// backup, wiped with the session.
abstract class AccessKeyRepository {
  /// The device's key, created on first use.
  Future<RepositoryResult<AccessKeyPair>> deviceKey();

  /// Replaces the device's key with a fresh one - the server refused the old.
  Future<RepositoryResult<AccessKeyPair>> regenerate();

  Future<RepositoryResult<bool>> isRegistered();

  Future<RepositoryResult<bool>> markRegistered(bool registered);

  /// The onion address and one-time private key from a version-2 link, held
  /// only until the pairing it was meant for has answered.
  Future<RepositoryResult<bool>> saveInvite({required String onion, required Uint8List oneTimeKey});

  Future<RepositoryResult<InviteAccess?>> invite();

  Future<RepositoryResult<bool>> clearInvite();
}

/// What a version-2 link lends a new device for one pairing.
class InviteAccess {
  const InviteAccess({required this.onion, required this.oneTimeKey});

  /// `<56>.onion:443`.
  final String onion;
  final Uint8List oneTimeKey;
}
