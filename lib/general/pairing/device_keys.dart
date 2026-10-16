import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nox_app/domain/model/session/device_key_pair.dart';
import 'package:nox_tor/secure_box.dart';

/// The device's own key pair, by RustSecureBox (phase 050).
///
/// Dart makes no key of its own: the pair comes from the module's
/// RustSecureBox - the same library the server runs - and so does the public
/// key of a private one. The private half never leaves the device: it goes to
/// the module's channel at every open, which signs the server's challenge with
/// it in POST /auth2, and only the public key ever travels.
///
/// ⚠️ The key is stored in the OS secure store and is therefore extractable by
/// something that already owns the device - recorded so that "private keys do
/// not travel" reads as "not over the wire", not "protected by hardware".
abstract final class DeviceKeys {
  /// RustSecureBox. A test may stand in for it; the app always has the native
  /// one.
  @visibleForTesting
  static SecureBoxApi box = const NativeSecureBoxApi();

  /// A new pair, base64 - what a device makes once, before its first pairing.
  static DeviceKeyPair generate() {
    final pair = box.generateKeys();
    try {
      return DeviceKeyPair(privateKey: base64.encode(pair.privateKey), publicKey: base64.encode(pair.publicKey));
    } finally {
      pair.privateKey.fillRange(0, pair.privateKey.length, 0);
    }
  }

  /// The public key RustSecureBox gives for [privateKey], both base64.
  static String publicKeyOf(String privateKey) {
    final private = Uint8List.fromList(base64.decode(privateKey));
    try {
      return base64.encode(box.getChallenge(private).publicKey);
    } finally {
      private.fillRange(0, private.length, 0);
    }
  }

  /// Whether this build's RustSecureBox makes [pair]: its public key is the
  /// one the box gives for its private one. A private key the box refuses
  /// outright is not one either. Any other failure of the box is thrown - it
  /// says nothing about the pair.
  static bool isOwn(DeviceKeyPair pair) {
    try {
      return publicKeyOf(pair.privateKey) == pair.publicKey;
    } on SecureBoxException catch (error) {
      if (error.code == SecureBoxCode.invalidArgument) return false;
      rethrow;
    }
  }
}
