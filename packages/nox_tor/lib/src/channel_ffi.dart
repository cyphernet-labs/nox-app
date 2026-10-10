import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'channel_core.dart';
import 'nox_tor_bindings.dart';

/// The channels of this isolate over the native module.
///
/// The module posts every event of this isolate's channels to ONE native port
/// of the isolate, never closed. It does not keep the isolate alive, and it
/// dies with it - and then the module's posts are refused, and the module ends
/// those channels itself. A function of the isolate's, which a
/// `NativeCallable` would be, cannot be used for this: it is deleted with the
/// isolate, and the VM aborts the process on the next call into it, while the
/// module's channels outlive any isolate - a hot restart, an engine Android
/// tears down on Back, leave them running in the same process.
///
/// Statics are per isolate, so each isolate that opens channels gets its own
/// port and its own registry. The first thing each one does is end the
/// channels an isolate before it left behind.
final ChannelCore ffiChannelCore = _startCore();

ChannelCore _startCore() {
  noxChanReap();
  return ChannelCore(const FfiChannelAbi());
}

final RawReceivePort _events = RawReceivePort(_dispatch, 'nox_chan events')..keepIsolateAlive = false;

/// The header of an event message: handle (8), kind (4), code (4), in this
/// machine's byte order; the bytes of an OPEN or a DATA follow.
const int _header = 16;

void _dispatch(Object? message) {
  if (message is! Uint8List || message.length < _header) return;
  final header = ByteData.sublistView(message, 0, _header);
  final kind = header.getInt32(8, Endian.host);
  if (kind == ChannelEvent.probe) return;
  final bytes = kind == ChannelEvent.open || kind == ChannelEvent.data ? Uint8List.sublistView(message, _header) : null;
  ffiChannelCore.deliver(header.getInt64(0, Endian.host), kind, bytes, header.getInt32(12, Endian.host));
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
      return noxChanOpen(targetKind, hostText, port, seed, key, timeoutMs, NativeApi.postCObject, _events.sendPort.nativePort);
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
