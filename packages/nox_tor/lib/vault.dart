/// The vault of the native module (phase 048), as Dart sees it: what the app
/// keeps on the device's disk, sealed under the local-database key.
///
/// The app reads the key from the system keystore and hands it over once with
/// [NoxVault.setKey]; [NoxVault.clear] wipes it from the module. In between, a
/// record of the local database goes through [NoxVault.seal] and
/// [NoxVault.open], and a file - an attachment, a copy of an outgoing one -
/// chunk by chunk through [NoxVault.sealChunk] and [NoxVault.openChunk]. What a
/// record and a chunk are, byte for byte, is the module's
/// (specs/048-device-data-at-rest/contracts/ffi-vault.md); the file around the
/// chunks is the app's.
///
/// Every call is synchronous - a Sembast codec cannot wait - and copies what
/// the module hands back into Dart memory, freeing the module's buffer at
/// once. The key is the module's, one for the whole process: every isolate
/// seals and opens with the key set last.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'src/vault_bindings.dart';

/// Why a vault call failed: the C ABI's returns, named.
enum VaultCode {
  /// Forged, cut short, or sealed under another key - there is no telling
  /// which - or sealed for another file, another index or the other `last`.
  /// It does not open.
  forged(-4),

  /// A key, a name or an index the vault does not take.
  invalidArgument(-7),

  /// No key is set: none was, or it was cleared.
  noKey(-9),

  /// Inside the module, what should not happen did.
  internal(-11);

  const VaultCode(this.value);

  /// The C ABI's return.
  final int value;

  /// The code of a C ABI return; one the contract does not name is [internal].
  static VaultCode of(int value) {
    for (final code in values) {
      if (code.value == value) return code;
    }
    return internal;
  }
}

/// A vault call that did not succeed. Carries its code and nothing else:
/// anything more could name a file or quote what was sealed, and exceptions
/// end up in logs.
class VaultException implements Exception {
  const VaultException(this.code);

  final VaultCode code;

  @override
  String toString() => 'VaultException(${code.name})';
}

abstract final class NoxVault {
  /// The length of the key.
  static const int keyLength = 32;

  /// What sealing adds to a record: its nonce (12) and its tag (16).
  static const int recordOverhead = 28;

  /// What sealing adds to a chunk: its tag.
  static const int chunkOverhead = 16;

  /// Hands the key over, in place of any key set before. A key of another
  /// length, or of all zeros, is [VaultCode.invalidArgument] and leaves the
  /// vault as it was.
  ///
  /// The native copy made for the call is wiped right after it; the module
  /// keeps its own, in a buffer it wipes on [clear].
  static void setKey(Uint8List key32) {
    if (key32.length != keyLength) throw const VaultException(VaultCode.invalidArgument);
    using((arena) {
      final key = arena<Uint8>(keyLength);
      final bytes = key.asTypedList(keyLength);
      try {
        bytes.setAll(0, key32);
        _check(noxVaultSetKey(key));
      } finally {
        bytes.fillRange(0, keyLength, 0);
      }
    });
  }

  /// Wipes the key from the module: every call after is [VaultCode.noKey]
  /// until the next [setKey].
  static void clear() => noxVaultClear();

  /// A record sealed: nonce (12), ciphertext, tag (16) - a fresh nonce each
  /// time, so one record sealed twice is two different results.
  static Uint8List seal(Uint8List data) =>
      using((arena) => _run(arena, data, (input, length, out, outLength) => noxVaultSeal(input, length, out, outLength)));

  /// The record [seal] made. [VaultCode.forged] when it was changed, cut or
  /// sealed under another key.
  static Uint8List open(Uint8List data) =>
      using((arena) => _run(arena, data, (input, length, out, outLength) => noxVaultOpen(input, length, out, outLength)));

  /// Chunk [index] of the file [name], sealed: ciphertext, tag (16). [last]
  /// says whether it ends the file.
  ///
  /// [name] goes into the file's key, so it stays the file's for the life of
  /// the file's bytes: the hex of the random 16-byte id in the file's header,
  /// not a path, which changes when the file moves. The chunk's nonce is its
  /// index, so [name] is the name of ONE content: a chunk is sealed once it is
  /// whole, and different bytes never go under a name and index used before.
  /// [name] must not be empty or hold a NUL; an [index] must not be negative.
  static Uint8List sealChunk(String name, int index, {required bool last, required Uint8List data}) {
    _checkChunk(name, index);
    return using((arena) {
      final nativeName = name.toNativeUtf8(allocator: arena);
      final flag = last ? 1 : 0;
      return _run(
        arena,
        data,
        (input, length, out, outLength) => noxVaultSealChunk(nativeName, index, flag, input, length, out, outLength),
      );
    });
  }

  /// The bytes of chunk [index] of the file [name]. [VaultCode.forged] when the
  /// chunk was changed, cut or sealed under another key - or sealed for
  /// another file, another index, or as the last chunk when [last] says it is
  /// not, or the other way round: how a file cut at a chunk boundary shows.
  static Uint8List openChunk(String name, int index, {required bool last, required Uint8List data}) {
    _checkChunk(name, index);
    return using((arena) {
      final nativeName = name.toNativeUtf8(allocator: arena);
      final flag = last ? 1 : 0;
      return _run(
        arena,
        data,
        (input, length, out, outLength) => noxVaultOpenChunk(nativeName, index, flag, input, length, out, outLength),
      );
    });
  }

  /// A name the module would read as another - cut at a NUL - or as every
  /// file's, and an index it would read as a huge one.
  static void _checkChunk(String name, int index) {
    if (name.isEmpty || name.contains('\u0000') || index < 0) throw const VaultException(VaultCode.invalidArgument);
  }

  static Uint8List _run(
    Arena arena,
    Uint8List data,
    int Function(Pointer<Uint8> input, int length, Pointer<Pointer<Uint8>> out, Pointer<UintPtr> outLength) call,
  ) {
    final Pointer<Uint8> input = data.isEmpty ? nullptr : arena<Uint8>(data.length);
    if (data.isNotEmpty) input.asTypedList(data.length).setAll(0, data);
    final out = arena<Pointer<Uint8>>();
    final outLength = arena<UintPtr>();
    _check(call(input, data.length, out, outLength));
    return _take(out.value, outLength.value);
  }

  /// What the module handed over, copied into Dart memory; the module's
  /// buffer is freed at once. An empty result is no buffer at all.
  static Uint8List _take(Pointer<Uint8> buffer, int length) {
    if (length == 0) return Uint8List(0);
    try {
      return Uint8List.fromList(buffer.asTypedList(length));
    } finally {
      noxVaultBufFree(buffer, length);
    }
  }

  static void _check(int code) {
    if (code != 0) throw VaultException(VaultCode.of(code));
  }
}
