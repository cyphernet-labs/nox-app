import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// The device's own key pair, and the one thing it proves.
///
/// The private half is generated here and never leaves: it is not sent when
/// pairing, not sent when greeting, and not written to any log. What travels
/// is the public key and a signature — possession is demonstrated, never
/// handed over. That is the whole difference from the identifier sign-in this
/// replaces, where the secret itself travelled through clipboards and QR codes.
///
/// ⚠️ The key is stored in the OS secure store and is therefore extractable by
/// something that already owns the device. A hardware enclave would need
/// native work on five platforms and is out of this phase — recorded so the
/// model's "private keys do not travel" reads as "not over the wire" rather
/// than "protected by hardware".
abstract final class DeviceKeys {
  /// Domain separation, contract §2. Without it a signature taken over a
  /// challenge would be a valid signature over the same bytes anywhere else
  /// the protocol later decides to sign something.
  static const String challengePrefix = 'nox/challenge/v1:';

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

  /// The public key for a seed, base64 — what the server stores as `device_key`.
  static Future<String> publicKey(String seed) async {
    final pair = await _keyPair(seed);
    final public = await pair.extractPublicKey();
    return base64.encode(public.bytes);
  }

  /// Signs the server's challenge.
  ///
  /// The RAW challenge bytes are signed, not their base64 spelling: two
  /// implementations disagreeing about padding would disagree about the
  /// signature, and one of them would be locked out for reasons neither side
  /// could see.
  static Future<String> signChallenge({required String seed, required String challenge}) async {
    final pair = await _keyPair(seed);
    final message = <int>[...utf8.encode(challengePrefix), ...base64.decode(challenge)];
    final signature = await _algorithm.sign(message, keyPair: pair);
    return base64.encode(signature.bytes);
  }

  static Future<SimpleKeyPair> _keyPair(String seed) => _algorithm.newKeyPairFromSeed(base64.decode(seed));
}
