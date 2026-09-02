import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Derives the `login_ref` a greeting carries: the value by which the server
/// recognises the PERSON behind a connection.
///
/// The formula is pinned by contract v0 §3, not chosen here. Determinism across
/// installs is a property of the wire, not an implementation detail of this
/// client: two independent installs of the same person must derive the same
/// string, or every reinstall silently splits one person in two and nothing on
/// either side notices. Changing any part of this without changing the contract
/// — and the pinned test vector with it — breaks that quietly.
///
/// The derivation is one-way on purpose. The login identifier is a bearer
/// secret ("anyone who has it can sign in as you"), so it never leaves the
/// device; the server keeps only this digest and treats it as an opaque lookup
/// key, computing and verifying nothing.
abstract final class IdentifierDigest {
  /// Domain separation, so the same secret hashed for some later purpose can
  /// never collide with this one. Quoted from contract v0 §3.
  static const String prefix = 'nox/login-ref/v1:';

  /// Lowercase hex SHA-256 over [prefix] + [identifier] in UTF-8; exactly 64
  /// characters. An empty identifier yields null: there is nothing to claim,
  /// and the greeting simply omits the field (contract §3 makes it optional).
  static String? loginRef(String? identifier) {
    if (identifier == null || identifier.isEmpty) return null;
    return sha256.convert(utf8.encode('$prefix$identifier')).toString();
  }
}
