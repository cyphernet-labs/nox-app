import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Does this certificate belong to the server the pairing link named?
///
/// One question, answered by comparing the hash of the certificate's public key
/// with the thirty-two bytes a person carried here by hand. Nothing else about
/// the certificate is consulted: not its name, not its dates, not who signed
/// it. A home server has no domain name to be issued a certificate for, its
/// address changes, and its owner may not touch it for years — so each of those
/// three would eventually become a refusal that cannot be explained or
/// repaired, while none of them says anything about WHICH machine answered.
///
/// Deliberately pure and deliberately total: it is called from inside the TLS
/// stack's certificate callback, where a thrown exception has no useful place
/// to go. Every unexpected input is a `false` — an answer, not an error.
class ServerPin {
  const ServerPin._();

  /// The fixed prefix of a SubjectPublicKeyInfo holding an ECDSA P-256 key:
  /// the SEQUENCE header, the `id-ecPublicKey` and `prime256v1` OIDs, and the
  /// BIT STRING header of the 65-byte uncompressed point that follows.
  ///
  /// A full ASN.1 parser would be the general answer and is not needed for one
  /// fixed shape. The curve is named in the contract (§8A), so a different
  /// curve would be a different wire format rather than a case to handle here.
  static const List<int> _p256SpkiPrefix = <int>[
    0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, //
    0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, //
    0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, //
    0x42, 0x00,
  ];

  /// Total length of that SubjectPublicKeyInfo: the 26-byte prefix above plus
  /// the 65-byte uncompressed point.
  static const int _spkiLength = 26 + 65;

  /// True when [der] carries the key whose fingerprint is [fingerprint].
  ///
  /// [fingerprint] is base64 of sha256 over the SubjectPublicKeyInfo — the
  /// value the pairing link carried. A null or empty one is a REFUSAL, never a
  /// waiver: an install with nothing to compare against is exactly the install
  /// that must not connect.
  static bool matches(List<int>? der, String? fingerprint) {
    if (fingerprint == null || fingerprint.isEmpty) return false;
    if (der == null) return false;

    final start = _indexOfSpki(der);
    if (start < 0) return false;
    // The prefix may appear near the end of a truncated or malformed
    // certificate. Requiring the whole key after it is what keeps this from
    // hashing a short read and comparing the result to anything.
    if (der.length - start < _spkiLength) return false;

    final spki = der.sublist(start, start + _spkiLength);
    return base64.encode(sha256.convert(spki).bytes) == fingerprint;
  }

  /// The FIRST occurrence, and only the first.
  ///
  /// A certificate holds exactly one subject public key; anything further in
  /// carrying the same bytes is an extension or an issuer field, and searching
  /// on past the real one would let a crafted certificate nominate which key it
  /// is judged by.
  static int _indexOfSpki(List<int> der) {
    final limit = der.length - _p256SpkiPrefix.length;
    outer:
    for (var i = 0; i <= limit; i++) {
      for (var j = 0; j < _p256SpkiPrefix.length; j++) {
        if (der[i + j] != _p256SpkiPrefix[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}
