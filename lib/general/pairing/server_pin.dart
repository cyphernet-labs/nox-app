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
  /// A CHECK, never a locator. The curve is named in the contract (§8A), so a
  /// certificate carrying anything else is not this server; but which bytes to
  /// check is decided by walking the certificate, not by looking for these.
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

    final spki = _subjectPublicKeyInfo(der);
    if (spki == null) return false;
    // The curve the contract names. Checked on the key the certificate really
    // has, so this decides nothing about WHICH bytes are hashed.
    if (spki.length != _spkiLength) return false;
    for (var i = 0; i < _p256SpkiPrefix.length; i++) {
      if (spki[i] != _p256SpkiPrefix[i]) return false;
    }
    return base64.encode(sha256.convert(spki).bytes) == fingerprint;
  }

  /// The certificate's ACTUAL subjectPublicKeyInfo, found by position.
  ///
  /// This walks the DER rather than searching it, and the difference is the
  /// whole security of the check. `Certificate` is a SEQUENCE whose first
  /// element is the `TBSCertificate`, and inside that the fields are ordered:
  ///
  ///     version [0] EXPLICIT (optional)
  ///     serialNumber         INTEGER
  ///     signature            SEQUENCE
  ///     issuer               SEQUENCE
  ///     validity             SEQUENCE
  ///     subject              SEQUENCE
  ///     subjectPublicKeyInfo SEQUENCE   <- this one, the seventh
  ///
  /// **The issuer and the subject come BEFORE the key.** An earlier version of
  /// this file looked for the fixed P-256 header and took the first hit,
  /// reasoning that anything further along would be an extension. That is the
  /// wrong way round, and it was exploitable: a certificate on somebody else's
  /// key, carrying a verbatim copy of the real server's SubjectPublicKeyInfo
  /// planted in its own subject, hashed to the pinned fingerprint and was
  /// accepted — over both transports, with nothing on screen to suggest it. The
  /// bytes needed to build that plant are public: every client that dials the
  /// real server is handed them. `planted.der` in the fixtures is exactly this
  /// certificate, and a test holds the door shut.
  ///
  /// No general ASN.1 parser: only the tag-length-value walk those seven fields
  /// need. Anything it cannot read is a `null`, which [matches] turns into a
  /// refusal.
  static List<int>? _subjectPublicKeyInfo(List<int> der) {
    const sequence = 0x30;
    const integer = 0x02;
    const contextZero = 0xA0;

    final certificate = _readTlv(der, 0, der.length);
    if (certificate == null || certificate.tag != sequence) return null;
    final tbs = _readTlv(der, certificate.contentStart, certificate.end);
    if (tbs == null || tbs.tag != sequence) return null;

    var at = tbs.contentStart;
    final limit = tbs.end;

    var field = _readTlv(der, at, limit);
    if (field == null) return null;
    // version is optional and defaulted, so it may simply not be there.
    if (field.tag == contextZero) {
      at = field.end;
      field = _readTlv(der, at, limit);
      if (field == null) return null;
    }
    if (field.tag != integer) return null; // serialNumber
    at = field.end;
    // signature, issuer, validity, subject: four SEQUENCEs, in that order.
    for (var i = 0; i < 4; i++) {
      final skipped = _readTlv(der, at, limit);
      if (skipped == null || skipped.tag != sequence) return null;
      at = skipped.end;
    }
    final spki = _readTlv(der, at, limit);
    if (spki == null || spki.tag != sequence) return null;
    // The WHOLE element, header included - that is what the other side hashes.
    return der.sublist(spki.start, spki.end);
  }

  /// Reads one tag-length-value at [at], or null if it does not fit in [limit].
  static _Tlv? _readTlv(List<int> der, int at, int limit) {
    if (at < 0 || at + 2 > limit) return null;
    final tag = der[at];
    // A high-tag-number form cannot appear among the fields walked above, and
    // refusing it keeps this to one byte of tag.
    if (tag & 0x1F == 0x1F) return null;

    var cursor = at + 1;
    final first = der[cursor++];
    int length;
    if (first < 0x80) {
      length = first;
    } else {
      final count = first & 0x7F;
      // 0x80 is the indefinite form, which DER forbids outright; more than
      // four length bytes is a certificate far larger than any that exists.
      if (count == 0 || count > 4) return null;
      if (cursor + count > limit) return null;
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | der[cursor++];
      }
    }
    final end = cursor + length;
    if (length < 0 || end > limit) return null;
    return _Tlv(tag, at, cursor, end);
  }
}

/// One DER element: where it starts, where its content starts, where it ends.
class _Tlv {
  const _Tlv(this.tag, this.start, this.contentStart, this.end);

  final int tag;
  final int start;
  final int contentStart;
  final int end;
}
