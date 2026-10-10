import 'dart:convert';

import 'package:nox_tor/vault.dart';
import 'package:sembast/sembast.dart';

/// The codec of the local database (phase 048): every line of the file is a
/// record sealed by the vault - `base64(nonce ‖ ciphertext ‖ tag)` under the
/// key of records the module draws from the local-data key.
///
/// Sembast passes every line through it, its own first line included: that
/// one carries the [signature], sealed, and a database sealed under another
/// key fails to open on it (`DatabaseException.invalidCodec`) rather than
/// handing over records nobody can read. A record that was changed, cut or
/// sealed under another key is a [VaultException] - never a guess at what it
/// said.
///
/// Synchronous, as sembast needs: the vault's calls are.
class VaultCodec extends Codec<Object?, String> {
  const VaultCodec();

  /// What sembast seals into the database's first line.
  static const String signature = 'nox-vault-1';

  /// The codec as sembast takes it.
  static final SembastCodec sembast = SembastCodec(signature: signature, codec: const VaultCodec());

  @override
  Converter<Object?, String> get encoder => const _Seal();

  @override
  Converter<String, Object?> get decoder => const _Open();
}

class _Seal extends Converter<Object?, String> {
  const _Seal();

  @override
  String convert(Object? input) => base64.encode(NoxVault.seal(utf8.encode(json.encode(input))));
}

class _Open extends Converter<String, Object?> {
  const _Open();

  @override
  Object? convert(String input) => json.decode(utf8.decode(NoxVault.open(base64.decode(input))));
}
