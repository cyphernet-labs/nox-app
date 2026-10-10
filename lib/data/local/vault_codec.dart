import 'dart:convert';
import 'dart:typed_data';

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

/// JSON straight to and from UTF-8 bytes, with no string in between: the
/// database opens every one of its lines at the start (SC-003).
final Converter<Object?, List<int>> _toJsonBytes = JsonUtf8Encoder();
final Converter<List<int>, Object?> _fromJsonBytes = utf8.decoder.fuse(json.decoder);

class _Seal extends Converter<Object?, String> {
  const _Seal();

  @override
  String convert(Object? input) => base64.encode(NoxVault.seal(Uint8List.fromList(_toJsonBytes.convert(input))));
}

class _Open extends Converter<String, Object?> {
  const _Open();

  @override
  Object? convert(String input) => _fromJsonBytes.convert(NoxVault.open(base64.decode(input)));
}
