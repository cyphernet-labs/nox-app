// The C ABI of the embedded Tor client - specs/040-tor-app/contracts/ffi.md.
//
// The asset id is this library's URI, which is what the build hook names the
// Rust library (`assetName: 'src/nox_tor_bindings.dart'`). Every function is
// short and never calls back into Dart, hence isLeaf.
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

@Native<Int32 Function(Pointer<Utf8>, Uint16, Pointer<Uint8>)>(symbol: 'nox_tor_set_target', isLeaf: true)
external int noxTorSetTarget(Pointer<Utf8> onionHost, int port, Pointer<Uint8> clientKey32);

@Native<Int32 Function()>(symbol: 'nox_tor_clear_target', isLeaf: true)
external int noxTorClearTarget();

@Native<Void Function(Bool)>(symbol: 'nox_tor_set_dormant', isLeaf: true)
external void noxTorSetDormant(bool dormant);

@Native<Int32 Function(Pointer<NoxTorStatusStruct>)>(symbol: 'nox_tor_status', isLeaf: true)
external int noxTorStatus(Pointer<NoxTorStatusStruct> out);

@Native<Int32 Function(Pointer<Uint8>)>(symbol: 'nox_tor_bridge_secret', isLeaf: true)
external int noxTorBridgeSecret(Pointer<Uint8> out32);

@Native<Int32 Function(Pointer<Uint8>, Pointer<Utf8>, Size)>(symbol: 'nox_tor_onion_from_pubkey', isLeaf: true)
external int noxTorOnionFromPubkey(Pointer<Uint8> pub32, Pointer<Utf8> out, int outLen);

@Native<Pointer<Utf8> Function()>(symbol: 'nox_tor_version', isLeaf: true)
external Pointer<Utf8> noxTorVersion();
