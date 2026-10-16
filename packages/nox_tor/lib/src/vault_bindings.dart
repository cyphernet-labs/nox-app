// The C ABI of the vault (specs/048-device-data-at-rest/contracts/ffi-vault.md):
// what the app keeps on the device's disk, sealed under the local-database key.
//
// The vault is part of the one library the build hook builds, whose asset id
// is named after nox_tor_bindings.dart - hence the default asset of this
// library. Every function is synchronous and short, and none calls back into
// Dart, hence isLeaf.
@DefaultAsset('package:nox_tor/src/nox_tor_bindings.dart')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

@Native<Int32 Function(Pointer<Uint8>)>(symbol: 'nox_vault_set_key', isLeaf: true)
external int noxVaultSetKey(Pointer<Uint8> key32);

@Native<Void Function()>(symbol: 'nox_vault_clear', isLeaf: true)
external void noxVaultClear();

@Native<Int32 Function(Pointer<Uint8>, UintPtr, Pointer<Pointer<Uint8>>, Pointer<UintPtr>)>(symbol: 'nox_vault_seal', isLeaf: true)
external int noxVaultSeal(Pointer<Uint8> data, int len, Pointer<Pointer<Uint8>> out, Pointer<UintPtr> outLen);

@Native<Int32 Function(Pointer<Uint8>, UintPtr, Pointer<Pointer<Uint8>>, Pointer<UintPtr>)>(symbol: 'nox_vault_open', isLeaf: true)
external int noxVaultOpen(Pointer<Uint8> data, int len, Pointer<Pointer<Uint8>> out, Pointer<UintPtr> outLen);

@Native<Int32 Function(Pointer<Utf8>, Uint64, Int32, Pointer<Uint8>, UintPtr, Pointer<Pointer<Uint8>>, Pointer<UintPtr>)>(
  symbol: 'nox_vault_seal_chunk',
  isLeaf: true,
)
external int noxVaultSealChunk(
  Pointer<Utf8> name,
  int index,
  int last,
  Pointer<Uint8> data,
  int len,
  Pointer<Pointer<Uint8>> out,
  Pointer<UintPtr> outLen,
);

@Native<Int32 Function(Pointer<Utf8>, Uint64, Int32, Pointer<Uint8>, UintPtr, Pointer<Pointer<Uint8>>, Pointer<UintPtr>)>(
  symbol: 'nox_vault_open_chunk',
  isLeaf: true,
)
external int noxVaultOpenChunk(
  Pointer<Utf8> name,
  int index,
  int last,
  Pointer<Uint8> data,
  int len,
  Pointer<Pointer<Uint8>> out,
  Pointer<UintPtr> outLen,
);

/// `nox_chan_buf_free`, which frees what the vault hands over as well: one
/// allocator, the module's. Bound here too, so the vault leans on nothing of
/// the channel's bindings.
@Native<Void Function(Pointer<Uint8>, UintPtr)>(symbol: 'nox_chan_buf_free', isLeaf: true)
external void noxVaultBufFree(Pointer<Uint8> data, int len);
