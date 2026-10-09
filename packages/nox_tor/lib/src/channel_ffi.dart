import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'channel_core.dart';
import 'nox_tor_bindings.dart';

/// The channels of this isolate over the native module.
///
/// ONE event callback for every channel of the isolate, never closed: the
/// module may call it at any moment until the last channel's CLOSED. It does
/// not keep the isolate alive on its own. Statics are per isolate, so each
/// isolate that opens channels gets its own callback and its own registry.
final ChannelCore ffiChannelCore = ChannelCore(const FfiChannelAbi());

final NativeCallable<NoxChanEventNative> _events = NativeCallable<NoxChanEventNative>.listener(_dispatch)..keepIsolateAlive = false;

void _dispatch(int handle, int kind, Pointer<Uint8> data, int len, int code) {
  Uint8List? bytes;
  if ((kind == ChannelEvent.open || kind == ChannelEvent.data) && data != nullptr) {
    // Copied out and freed at once: the module allocated it for this event
    // alone, and Dart owns it from here - whether or not anybody still holds
    // the channel it names.
    bytes = len == 0 ? Uint8List(0) : Uint8List.fromList(data.asTypedList(len));
    noxChanBufFree(data, len);
  }
  ffiChannelCore.deliver(handle, kind, bytes, code);
}

/// [ChannelAbi] over `nox_chan_*`.
class FfiChannelAbi implements ChannelAbi {
  const FfiChannelAbi();

  @override
  int open(int targetKind, String host, int port, Uint8List deviceSeed, Uint8List serverKey, int timeoutMs) {
    final seed = malloc<Uint8>(32);
    final key = malloc<Uint8>(32);
    final hostText = host.toNativeUtf8(allocator: malloc);
    try {
      seed.asTypedList(32).setAll(0, deviceSeed);
      key.asTypedList(32).setAll(0, serverKey);
      return noxChanOpen(targetKind, hostText, port, seed, key, timeoutMs, _events.nativeFunction);
    } finally {
      // The seed is this device's private key: no copy of it outlives the
      // call. The module keeps its own, in a buffer it wipes.
      seed.asTypedList(32).fillRange(0, 32, 0);
      malloc.free(seed);
      malloc.free(key);
      malloc.free(hostText);
    }
  }

  @override
  int write(int handle, Uint8List bytes) {
    final buffer = malloc<Uint8>(bytes.length);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      return noxChanWrite(handle, buffer, bytes.length);
    } finally {
      malloc.free(buffer);
    }
  }

  @override
  int ack(int handle, int length) => noxChanAck(handle, length);

  @override
  int flush(int handle, int ticket) => noxChanFlush(handle, ticket);

  @override
  int shutdownWrite(int handle) => noxChanShutdownWrite(handle);

  @override
  int close(int handle) => noxChanClose(handle);
}
