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
/// events through ONE `NativeCallable.listener` per isolate.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'src/nox_tor_bindings.dart';

/// Where a channel goes.
sealed class ChannelTarget {
  const ChannelTarget();

  String get host;
  int get port;
}

/// TCP to [host] - an IP literal or a name - and [port].
final class DirectTarget extends ChannelTarget {
  const DirectTarget(this.host, this.port);

  @override
  final String host;

  @override
  final int port;

  @override
  bool operator ==(Object other) => other is DirectTarget && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);

  @override
  String toString() => 'DirectTarget($host:$port)';
}

/// A Tor stream to the onion service [host] (`<56>.onion`), always port 443.
final class OnionTarget extends ChannelTarget {
  const OnionTarget(this.host);

  @override
  final String host;

  @override
  int get port => 443;

  @override
  bool operator ==(Object other) => other is OnionTarget && other.host == host;

  @override
  int get hashCode => host.hashCode;

  /// Without the host: an onion address is never written anywhere it could
  /// be read back from.
  @override
  String toString() => 'OnionTarget([onion])';
}

/// Why a channel did not open, or why it closed: the `code` of the contract's
/// CLOSED event, in its order (`network` is 1).
enum ChannelFailure {
  /// The transport did not come up, or broke.
  network,

  /// Not done within the open's timeout.
  timeout,

  /// The TLS handshake failed.
  tls,

  /// An Eidolon message of the wrong length or with a bad signature - which is
  /// what a machine in the middle looks like - or a peer that does not speak
  /// the channel at all.
  protocol,

  /// The server proved a key other than the one the pairing link named.
  wrongServer,

  /// Tor is not up.
  torNotReady,

  /// The onion address is malformed.
  torOnionInvalid,

  /// The onion service was not found.
  torOnionNotFound,

  /// The onion service exists but does not answer.
  torOnionUnreachable,

  /// The onion service refused the Tor access key (until phase 045).
  torClientAuth,

  /// Something failed inside the module.
  internal;

  /// The kind a CLOSED `code` names; null for 0, closed normally. A code this
  /// build does not know is [internal].
  static ChannelFailure? fromCode(int code) {
    if (code == 0) return null;
    if (code < 1 || code > values.length) return internal;
    return values[code - 1];
  }
}

/// A channel that did not open. Carries the kind only - never an address, a
/// key or anything the module said about them.
class ChannelOpenException implements Exception {
  const ChannelOpenException(this.failure);

  final ChannelFailure failure;

  @override
  String toString() => 'ChannelOpenException(${failure.name})';
}

/// A channel that opened and then failed - reported on [NoxChannel.incoming]
/// after every byte that arrived before the failure.
class ChannelLostException implements Exception {
  const ChannelLostException(this.failure);

  final ChannelFailure failure;

  @override
  String toString() => 'ChannelLostException(${failure.name})';
}

/// The window of a channel, each way: the module holds at most this much
/// unacknowledged incoming data, and [NoxChannel.writable] holds a writer back
/// while more than this is queued to go out.
const int channelWindowBytes = 1 << 20;

/// Opens channels.
abstract interface class NoxChannelApi {
  /// Opens a channel to [target]; completes once it is verified (the server
  /// proved [serverKey], and this device proved the key of [deviceSeed]), or
  /// fails with [ChannelOpenException].
  ///
  /// [timeout] bounds transport, TLS and the check together. [cancel], when it
  /// completes first, abandons the open: the module drops it at once rather
  /// than at the end of [timeout] - how a caller that has stopped waiting, a
  /// connection pool timing a connect out, keeps nothing open behind its
  /// back.
  Future<NoxChannel> open(
    ChannelTarget target, {
    required Uint8List deviceSeed,
    required Uint8List serverKey,
    required Duration timeout,
    Future<void>? cancel,
  });
}

/// One verified connection to the server.
abstract interface class NoxChannel {
  /// The bytes the server sent. Done at the server's end of sending; an error
  /// ([ChannelLostException]) when the channel failed first. Single
  /// subscription; pausing it stops the module reading after one window.
  Stream<Uint8List> get incoming;

  /// Queues [bytes] to go out and returns how much is queued after the write.
  /// Throws [StateError] once the channel is closed or its sending is shut.
  int write(Uint8List bytes);

  /// Completes at once while the queue is within the window, else when it has
  /// drained to half of it.
  Future<void> get writable;

  /// Completes once everything queued before the call is written out; fails
  /// if the channel closes first.
  Future<void> flush();

  /// Ends sending after the queue (TLS `close_notify`); reading goes on.
  void shutdownWrite();

  /// Ends the channel at once.
  void close();

  /// Completes when the channel is gone: null when it closed normally, the
  /// kind when it failed.
  Future<ChannelFailure?> get closed;
}

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
  }) async {
    // Everything up to the registration below runs before this method first
    // yields, so no event of the new handle can be dispatched ahead of it.
    if (deviceSeed.length != 32) throw ArgumentError.value(deviceSeed.length, 'deviceSeed', 'must be 32 bytes');
    if (serverKey.length != 32) throw ArgumentError.value(serverKey.length, 'serverKey', 'must be 32 bytes');
    if (target.host.isEmpty || target.host.contains('\u0000')) throw ArgumentError.value('', 'target', 'needs a host');
    if (target.port < 1 || target.port > 0xFFFF) throw ArgumentError.value(target.port, 'target', 'port out of range');
    if (timeout <= Duration.zero) throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    final channel = _NativeChannel.open(target, deviceSeed: deviceSeed, serverKey: serverKey, timeout: timeout);
    cancel?.then((_) => channel._abandon(ChannelFailure.timeout), onError: (Object _) {});
    return channel._opening.future;
  }
}

/// Event kinds and return codes of the C ABI.
const int _kOpen = 1;
const int _kData = 2;
const int _kWritable = 3;
const int _kDrained = 4;
const int _kEof = 5;
const int _kClosed = 6;
const int _kInvalidArgument = -7;

/// One channel of the native module.
///
/// The state machine around one handle: the open, the incoming backlog that
/// is held back unacknowledged while nobody reads, the write window, and the
/// flush tickets. Everything is driven by events the module posts to this
/// isolate; none of them is handled before the call that caused it returns.
final class _NativeChannel implements NoxChannel {
  _NativeChannel._(this._handle, this._expectedKey, Duration timeout) {
    // A pending open is an error nobody may be listening to by the time it
    // fails - a caller that gave up. Marked handled; whoever does listen
    // still receives it.
    _opening.future.ignore();
    // The module bounds the open itself. This is the Dart side's own guard
    // over a module that never answered: past it, the open is abandoned.
    _guard = Timer(timeout + _openGrace, () => _abandon(ChannelFailure.timeout));
  }

  factory _NativeChannel.open(
    ChannelTarget target, {
    required Uint8List deviceSeed,
    required Uint8List serverKey,
    required Duration timeout,
  }) {
    final seed = malloc<Uint8>(32);
    final key = malloc<Uint8>(32);
    final host = target.host.toNativeUtf8(allocator: malloc);
    final int handle;
    try {
      seed.asTypedList(32).setAll(0, deviceSeed);
      key.asTypedList(32).setAll(0, serverKey);
      handle = noxChanOpen(
        target is OnionTarget ? 1 : 0,
        host,
        target.port,
        seed,
        key,
        timeout.inMilliseconds.clamp(1, 0xFFFFFFFF),
        _events.nativeFunction,
      );
    } finally {
      // The seed is this device's private key: no copy of it outlives the
      // call. The module keeps its own, in a buffer it wipes.
      seed.asTypedList(32).fillRange(0, 32, 0);
      malloc.free(seed);
      malloc.free(key);
      malloc.free(host);
    }
    if (handle == _kInvalidArgument) throw ArgumentError('the channel module refused the arguments');
    if (handle <= 0) throw const ChannelOpenException(ChannelFailure.internal);
    final channel = _NativeChannel._(handle, Uint8List.fromList(serverKey), timeout);
    _registry[handle] = channel;
    return channel;
  }

  /// How much longer than the module's own deadline the Dart side waits.
  static const Duration _openGrace = Duration(seconds: 5);

  /// The open channels of this isolate, by handle. An entry lives until its
  /// CLOSED: events for it may arrive until then, and their buffers are this
  /// side's to free.
  static final Map<int, _NativeChannel> _registry = <int, _NativeChannel>{};

  /// ONE callback for every channel of this isolate, never closed: the module
  /// may call it at any moment until the last channel's CLOSED. It does not
  /// keep the isolate alive on its own.
  static final NativeCallable<NoxChanEventNative> _events = NativeCallable<NoxChanEventNative>.listener(_dispatch)
    ..keepIsolateAlive = false;

  static void _dispatch(int handle, int kind, Pointer<Uint8> data, int len, int code) {
    Uint8List? bytes;
    if ((kind == _kOpen || kind == _kData) && data != nullptr) {
      // Copied out and freed at once: the module allocated it for this event
      // alone, and Dart owns it from here.
      bytes = len == 0 ? Uint8List(0) : Uint8List.fromList(data.asTypedList(len));
      noxChanBufFree(data, len);
    }
    final channel = _registry[handle];
    if (channel == null) return;
    try {
      switch (kind) {
        case _kOpen:
          channel._onOpen(bytes);
        case _kData:
          if (bytes != null && bytes.isNotEmpty) channel._onData(bytes);
        case _kWritable:
          channel._onWritable();
        case _kDrained:
          channel._onDrained(code);
        case _kEof:
          channel._onEof();
        case _kClosed:
          channel._onClosed(code);
      }
    } on Object {
      // An event must never take the isolate down; the channel's own state
      // says what happened, and a bad one ends in CLOSED like any other.
    }
  }

  final int _handle;

  /// The key the server must prove; the module checks it, and the OPEN event
  /// is checked against it once more here.
  final Uint8List _expectedKey;

  final Completer<NoxChannel> _opening = Completer<NoxChannel>();
  final Completer<ChannelFailure?> _closed = Completer<ChannelFailure?>();
  late final Timer _guard;

  late final StreamController<Uint8List> _incoming = StreamController<Uint8List>(
    onListen: _onListen,
    onPause: () => _paused = true,
    onResume: _onResume,
    onCancel: _onCancel,
  );

  bool _opened = false;
  bool _closeRequested = false;
  bool _writeShut = false;
  bool _gone = false;

  bool _listening = false;
  bool _paused = false;
  bool _cancelled = false;
  bool _incomingEnded = false;

  /// Incoming bytes nobody has taken yet: no listener, or a paused one. Not
  /// acknowledged, so the module stops reading after one window - this is
  /// what bounds memory when the receiver is slower than the network.
  final List<Uint8List> _backlog = <Uint8List>[];

  /// How the channel failed after it opened, for the incoming stream.
  ChannelFailure? _lostWith;

  int _queued = 0;
  Completer<void>? _writable;
  int _ticket = 0;
  final Map<int, Completer<void>> _flushes = <int, Completer<void>>{};

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  @override
  Future<ChannelFailure?> get closed => _closed.future;

  @override
  int write(Uint8List bytes) {
    if (_gone || _closeRequested || _writeShut) throw StateError('the channel is closed');
    if (bytes.isEmpty) return _queued;
    final buffer = malloc<Uint8>(bytes.length);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      final queued = noxChanWrite(_handle, buffer, bytes.length);
      if (queued < 0) throw StateError('the channel refused the write ($queued)');
      _queued = queued;
      return queued;
    } finally {
      malloc.free(buffer);
    }
  }

  @override
  Future<void> get writable {
    if (_gone) return Future<void>.error(StateError('the channel is closed'));
    if (_queued <= channelWindowBytes) return Future<void>.value();
    return (_writable ??= Completer<void>()).future;
  }

  @override
  Future<void> flush() {
    if (_gone || _closeRequested) return Future<void>.error(StateError('the channel is closed'));
    _ticket = _ticket >= 0x7FFFFFFF ? 1 : _ticket + 1;
    final ticket = _ticket;
    final drained = Completer<void>();
    _flushes[ticket] = drained;
    if (noxChanFlush(_handle, ticket) < 0) {
      _flushes.remove(ticket);
      return Future<void>.error(StateError('the channel is closed'));
    }
    return drained.future;
  }

  @override
  void shutdownWrite() {
    if (_gone || _closeRequested || _writeShut) return;
    _writeShut = true;
    noxChanShutdownWrite(_handle);
  }

  @override
  void close() {
    if (_gone || _closeRequested) return;
    _closeRequested = true;
    noxChanClose(_handle);
  }

  /// Gives up on an open that has not completed: it fails with [failure] and
  /// the module drops it. An open channel is left alone - it belongs to
  /// whoever it was handed to.
  void _abandon(ChannelFailure failure) {
    if (_opening.isCompleted) return;
    _guard.cancel();
    _opening.completeError(ChannelOpenException(failure));
    close();
  }

  void _onOpen(Uint8List? key) {
    if (_opening.isCompleted) return;
    // The module has compared the keys already. Compared again here because
    // this is the one fact everything after depends on, and the check costs
    // nothing next to the handshake behind it.
    if (key == null || key.length != _expectedKey.length) {
      _abandon(ChannelFailure.internal);
      return;
    }
    var same = true;
    for (var i = 0; i < key.length; i++) {
      if (key[i] != _expectedKey[i]) same = false;
    }
    if (!same) {
      _abandon(ChannelFailure.wrongServer);
      return;
    }
    _guard.cancel();
    _opened = true;
    _opening.complete(this);
  }

  void _onData(Uint8List bytes) {
    if (_incomingEnded) return;
    if (_cancelled) {
      // Nobody reads any more: let the module go on rather than stall a
      // channel whose other half may still be in use.
      _ack(bytes.length);
      return;
    }
    if (_listening && !_paused && _backlog.isEmpty) {
      _incoming.add(bytes);
      _ack(bytes.length);
      return;
    }
    _backlog.add(bytes);
  }

  void _onListen() {
    _listening = true;
    _drain();
  }

  void _onResume() {
    _paused = false;
    _drain();
  }

  void _onCancel() {
    _cancelled = true;
    for (final chunk in _backlog) {
      _ack(chunk.length);
    }
    _backlog.clear();
  }

  /// Hands the held bytes over while somebody takes them, acknowledging each
  /// as it goes - the backlog of a pause, or what arrived before a listener.
  void _drain() {
    while (_backlog.isNotEmpty && _listening && !_paused && !_cancelled && !_incomingEnded) {
      final chunk = _backlog.removeAt(0);
      _incoming.add(chunk);
      _ack(chunk.length);
    }
  }

  void _ack(int length) {
    if (_gone || length <= 0) return;
    noxChanAck(_handle, length);
  }

  void _onWritable() {
    // At most half a window is queued now. Overwritten by the next write.
    _queued = channelWindowBytes ~/ 2;
    final waiting = _writable;
    _writable = null;
    waiting?.complete();
  }

  void _onDrained(int ticket) => _flushes.remove(ticket)?.complete();

  void _onEof() => _endIncoming();

  void _onClosed(int code) {
    final failure = ChannelFailure.fromCode(code);
    _gone = true;
    _registry.remove(_handle);
    _guard.cancel();
    if (!_opening.isCompleted) {
      // Closed before it was verified. A normal close here is a close nobody
      // asked for; the open did not happen either way.
      _opening.completeError(ChannelOpenException(failure ?? ChannelFailure.network));
    }
    if (!_closed.isCompleted) _closed.complete(failure);
    final closedError = StateError('the channel is closed');
    final waiting = _writable;
    _writable = null;
    waiting?.completeError(closedError);
    for (final drained in _flushes.values) {
      drained.completeError(closedError);
    }
    _flushes.clear();
    if (_opened && failure != null) _lostWith = failure;
    _endIncoming();
  }

  /// The end of incoming data - the peer's EOF, or the channel's CLOSED. The
  /// held bytes go first, then the failure if there was one, then done; a
  /// listener that has not come yet receives all of it in order.
  void _endIncoming() {
    if (_incomingEnded) return;
    _incomingEnded = true;
    if (!_cancelled) {
      for (final chunk in _backlog) {
        _incoming.add(chunk);
        _ack(chunk.length);
      }
      final lost = _lostWith;
      if (lost != null) _incoming.addError(ChannelLostException(lost));
    }
    _backlog.clear();
    unawaited(_incoming.close());
  }
}
