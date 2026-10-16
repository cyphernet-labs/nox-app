/// RustSecureBox as Dart sees it (phase 050): the keys and signatures of the
/// check every connection to the server passes, POST /auth and POST /auth2.
///
/// The check itself runs inside the module's channel, which takes the device's
/// private key at every open; what the app does with keys OUTSIDE a channel
/// goes through here - making the device's pair once, before its first
/// pairing, and reading the public key of the private one it keeps, which is
/// what the server knows the device by. Dart computes no key or signature of
/// its own: the library is the module's, the same one the server runs.
///
/// Every call is synchronous and takes microseconds. A private key passes
/// through native memory that is wiped before it is freed.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'src/secure_box_bindings.dart';

/// Why a RustSecureBox call failed: the C ABI's returns, named.
enum SecureBoxCode {
  /// A key the library does not accept.
  invalidArgument(-1),

  /// No random bytes to be had.
  random(-2),

  /// Anything else inside the library, a panic included.
  internal(-3);

  const SecureBoxCode(this.value);

  /// The C ABI's return.
  final int value;

  /// The code of a C ABI return; one the contract does not name is [internal].
  static SecureBoxCode of(int value) {
    for (final code in values) {
      if (code.value == value) return code;
    }
    return internal;
  }
}

/// A RustSecureBox call that did not succeed. Carries its code and nothing
/// else: exceptions end up in logs, and nothing about a key may.
class SecureBoxException implements Exception {
  const SecureBoxException(this.code);

  final SecureBoxCode code;

  @override
  String toString() => 'SecureBoxException(${code.name})';
}

/// A new key pair. [privateKey] is the device's secret: it goes into the
/// system keystore and to the channel, and nowhere else.
final class SecureBoxKeyPair {
  const SecureBoxKeyPair({required this.privateKey, required this.publicKey});

  final Uint8List privateKey;
  final Uint8List publicKey;
}

/// The four functions of RustSecureBox.
abstract interface class SecureBoxApi {
  /// The lengths of the interface.
  static const int privateKeyLength = 32;
  static const int publicKeyLength = 32;
  static const int challengeLength = 32;
  static const int signatureLength = 64;

  /// A new key pair.
  SecureBoxKeyPair generateKeys();

  /// A new random challenge, and the public key of [privateKey].
  ({Uint8List challenge, Uint8List publicKey}) getChallenge(Uint8List privateKey);

  /// The signature of [privateKey] over the other side's [challenge].
  Uint8List signChallenge(Uint8List privateKey, Uint8List challenge);

  /// Whether [signature] is [publicKey]'s over [challenge].
  bool checkSignature(Uint8List publicKey, Uint8List challenge, Uint8List signature);
}

/// [SecureBoxApi] over the module's `nox_box_*`.
final class NativeSecureBoxApi implements SecureBoxApi {
  const NativeSecureBoxApi();

  @override
  SecureBoxKeyPair generateKeys() {
    return _with(
      const [],
      const [SecureBoxApi.privateKeyLength, SecureBoxApi.publicKeyLength],
      (_, outs) {
        return noxBoxGenerateKeys(outs[0], outs[1]);
      },
      (outs) => SecureBoxKeyPair(privateKey: outs[0], publicKey: outs[1]),
    );
  }

  @override
  ({Uint8List challenge, Uint8List publicKey}) getChallenge(Uint8List privateKey) {
    _length(privateKey, SecureBoxApi.privateKeyLength, 'privateKey');
    return _with([privateKey], const [SecureBoxApi.challengeLength, SecureBoxApi.publicKeyLength], (ins, outs) {
      return noxBoxGetChallenge(ins[0], outs[0], outs[1]);
    }, (outs) => (challenge: outs[0], publicKey: outs[1]));
  }

  @override
  Uint8List signChallenge(Uint8List privateKey, Uint8List challenge) {
    _length(privateKey, SecureBoxApi.privateKeyLength, 'privateKey');
    _length(challenge, SecureBoxApi.challengeLength, 'challenge');
    return _with([privateKey, challenge], const [SecureBoxApi.signatureLength], (ins, outs) {
      return noxBoxSignChallenge(ins[0], ins[1], outs[0]);
    }, (outs) => outs[0]);
  }

  @override
  bool checkSignature(Uint8List publicKey, Uint8List challenge, Uint8List signature) {
    _length(publicKey, SecureBoxApi.publicKeyLength, 'publicKey');
    _length(challenge, SecureBoxApi.challengeLength, 'challenge');
    _length(signature, SecureBoxApi.signatureLength, 'signature');
    var valid = false;
    _with([publicKey, challenge, signature], const [], (ins, _) {
      final code = noxBoxCheckSignature(ins[0], ins[1], ins[2]);
      if (code >= 0) valid = code == 1;
      return code < 0 ? code : 0;
    }, (_) {});
    return valid;
  }

  static void _length(Uint8List bytes, int length, String name) {
    if (bytes.length != length) throw ArgumentError.value(bytes.length, name, 'must be $length bytes');
  }

  /// Copies [inputs] into native memory, makes room for [outputs], runs [call]
  /// and reads the outputs back - every buffer wiped before it is freed,
  /// whatever happened.
  static T _with<T>(
    List<Uint8List> inputs,
    List<int> outputs,
    int Function(List<Pointer<Uint8>> ins, List<Pointer<Uint8>> outs) call,
    T Function(List<Uint8List> outs) read,
  ) {
    final ins = [for (final input in inputs) calloc<Uint8>(input.length)];
    final outs = [for (final length in outputs) calloc<Uint8>(length)];
    try {
      for (var i = 0; i < inputs.length; i++) {
        ins[i].asTypedList(inputs[i].length).setAll(0, inputs[i]);
      }
      final code = call(ins, outs);
      if (code != 0) throw SecureBoxException(SecureBoxCode.of(code));
      return read([for (var i = 0; i < outputs.length; i++) Uint8List.fromList(outs[i].asTypedList(outputs[i]))]);
    } finally {
      for (var i = 0; i < inputs.length; i++) {
        ins[i].asTypedList(inputs[i].length).fillRange(0, inputs[i].length, 0);
        calloc.free(ins[i]);
      }
      for (var i = 0; i < outputs.length; i++) {
        outs[i].asTypedList(outputs[i]).fillRange(0, outputs[i], 0);
        calloc.free(outs[i]);
      }
    }
  }
}
