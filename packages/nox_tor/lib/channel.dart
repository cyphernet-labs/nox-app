/// The secure channel of the native module (phase 044), as Dart sees it.
///
/// Every connection the app makes to its server - commands over `wss`, file
/// bytes over `https` - is built here, in layers: TCP to an address or a Tor
/// stream to an onion address, then TLS 1.3, then the Eidolon check that
/// decides who is on the other end. Not one byte of the caller's leaves before
/// the server has proved the key the pairing link named.
///
/// The module never blocks the caller (specs/044-secure-channel/contracts/
/// ffi-channel.md): `nox_chan_open` returns a handle at once, and everything
/// after - verified, data, room to write, drained, closed - comes back as
/// events posted to ONE native port per isolate, each a message of its own
/// that Dart owns outright. Incoming bytes are acknowledged as they are handed
/// to a listener that is not paused, which is what holds the module to one
/// window of unread data.
library;

import 'dart:typed_data';

import 'src/channel_ffi.dart';
import 'src/channel_types.dart';

export 'src/channel_types.dart';

/// [NoxChannelApi] over the native module.
///
/// Constructing it loads nothing: the library is looked up on the first open.
class NativeNoxChannelApi implements NoxChannelApi {
  const NativeNoxChannelApi();

  @override
  Future<NoxChannel> open(
    ChannelTarget target, {
    required Uint8List deviceSeed,
    required Uint8List serverKey,
    required Duration timeout,
    Future<void>? cancel,
  }) => ffiChannelCore.open(target, deviceSeed: deviceSeed, serverKey: serverKey, timeout: timeout, cancel: cancel);
}
