import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// The device's own Ed25519 key pair.
///
/// The private half is generated here and never leaves: not when pairing, not
/// when connecting, and not into any log. The seed is handed to the native
/// channel for each connection, which proves possession inside the Eidolon
/// check (phase 044) - the signatures are made in the module, over the
/// connection's own TLS exporter, and only the public key ever travels. That
/// is the whole difference from the identifier sign-in this replaced, where
/// the secret itself travelled through clipboards and QR codes.
///
/// ⚠️ The key is stored in the OS secure store and is therefore extractable by
/// something that already owns the device. A hardware enclave would need
/// native work on five platforms and is out of this phase — recorded so the
/// model's "private keys do not travel" reads as "not over the wire" rather
/// than "protected by hardware".
abstract final class DeviceKeys {
  static final Ed25519 _algorithm = Ed25519();

  /// Mints a new pair and returns its 32-byte seed, base64.
  ///
  /// The seed rather than the expanded private key: half the bytes, and the
  /// pair derives from it deterministically, so nothing is lost.
  static Future<String> generateSeed() async {
    final pair = await _algorithm.newKeyPair();
    final seed = await pair.extractPrivateKeyBytes();
    return base64.encode(seed);
  }

  /// The public key for a seed, base64 — what the server knows the device by,
  /// and what `device.revoke` names.
  static Future<String> publicKey(String seed) async {
    final pair = await _algorithm.newKeyPairFromSeed(base64.decode(seed));
    final public = await pair.extractPublicKey();
    return base64.encode(public.bytes);
  }
}
