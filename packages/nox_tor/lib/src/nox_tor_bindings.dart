// The C ABI of the native module: the embedded Tor client
// (specs/040-tor-app/contracts/ffi.md) and the secure channel
// (specs/044-secure-channel/contracts/ffi-channel.md).
//
// The asset id is this library's URI, which is what the build hook names the
// Rust library (`assetName: 'src/nox_tor_bindings.dart'`). The Tor functions
// are short and never call back into Dart, hence isLeaf. The channel functions
// may raise an event while they run - closing a channel answers with CLOSED -
// so only the one that only frees memory is a leaf.
import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// `NoxTorStatus` of the Rust side; eight bytes, field order is the ABI.
final class NoxTorStatusStruct extends Struct {
  @Uint8()
  external int state;

  @Uint8()
  external int bootstrapPercent;

  @Uint8()
  external int error;

  @Uint8()
  external int reserved;

  @Uint16()
  external int port;

  @Uint16()
  external int reserved2;
}

@Native<Int32 Function(Pointer<Utf8>, Pointer<Utf8>)>(symbol: 'nox_tor_start', isLeaf: true)
external int noxTorStart(Pointer<Utf8> stateDir, Pointer<Utf8> cacheDir);

@Native<Void Function()>(symbol: 'nox_tor_stop', isLeaf: true)
external void noxTorStop();

@Native<Void Function(Bool)>(symbol: 'nox_tor_set_dormant', isLeaf: true)
external void noxTorSetDormant(bool dormant);

@Native<Int32 Function(Pointer<NoxTorStatusStruct>)>(symbol: 'nox_tor_status', isLeaf: true)
external int noxTorStatus(Pointer<NoxTorStatusStruct> out);

@Native<Int32 Function(Pointer<Uint8>, Pointer<Utf8>, Size)>(symbol: 'nox_tor_onion_from_pubkey', isLeaf: true)
external int noxTorOnionFromPubkey(Pointer<Uint8> pub32, Pointer<Utf8> out, int outLen);

@Native<Pointer<Utf8> Function()>(symbol: 'nox_tor_version', isLeaf: true)
external Pointer<Utf8> noxTorVersion();

/// `nox_chan_event_fn`: (handle, kind, data, len, code). Called from the
/// module's threads; Dart receives it through a `NativeCallable.listener`.
typedef NoxChanEventNative = Void Function(Int64 handle, Int32 kind, Pointer<Uint8> data, UintPtr len, Int32 code);

@Native<Int64 Function(Int32, Pointer<Utf8>, Uint16, Pointer<Uint8>, Pointer<Uint8>, Uint32, Pointer<NativeFunction<NoxChanEventNative>>)>(
  symbol: 'nox_chan_open',
)
external int noxChanOpen(
  int targetKind,
  Pointer<Utf8> host,
  int port,
  Pointer<Uint8> deviceSeed32,
  Pointer<Uint8> serverKey32,
  int connectTimeoutMs,
  Pointer<NativeFunction<NoxChanEventNative>> onEvent,
);

@Native<Int64 Function(Int64, Pointer<Uint8>, UintPtr)>(symbol: 'nox_chan_write')
external int noxChanWrite(int handle, Pointer<Uint8> data, int len);

@Native<Int32 Function(Int64, UintPtr)>(symbol: 'nox_chan_ack')
external int noxChanAck(int handle, int len);

@Native<Int32 Function(Int64, Int32)>(symbol: 'nox_chan_flush')
external int noxChanFlush(int handle, int ticket);

@Native<Int32 Function(Int64)>(symbol: 'nox_chan_shutdown_write')
external int noxChanShutdownWrite(int handle);

@Native<Int32 Function(Int64)>(symbol: 'nox_chan_close')
external int noxChanClose(int handle);

@Native<Void Function(Pointer<Uint8>, UintPtr)>(symbol: 'nox_chan_buf_free', isLeaf: true)
external void noxChanBufFree(Pointer<Uint8> data, int len);
