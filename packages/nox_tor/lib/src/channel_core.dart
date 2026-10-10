import 'dart:async';
import 'dart:typed_data';

import 'channel_types.dart';

/// Event kinds of the C ABI (specs/044-secure-channel/contracts/ffi-channel.md).
abstract final class ChannelEvent {
  static const int open = 1;
  static const int data = 2;
  static const int writable = 3;
  static const int drained = 4;
  static const int eof = 5;
  static const int closed = 6;
}

/// Return codes of the C ABI.
abstract final class ChannelReturn {
  static const int invalidArgument = -7;
  static const int closed = -9;
}

/// The channel's C ABI as calls: the native one goes through FFI, a test's
/// stands in for the module. The seed and the key are the caller's - an
/// implementation copies what it keeps.
abstract class ChannelAbi {
  /// `nox_chan_open`: a handle above 0, or a negative code.
  int open(int targetKind, String host, int port, Uint8List deviceSeed, Uint8List serverKey, int timeoutMs);

  /// `nox_chan_write`: the queue's size after the write, or a negative code.
  int write(int handle, Uint8List bytes);

  int ack(int handle, int length);

  int flush(int handle, int ticket);

  int shutdownWrite(int handle);

  int close(int handle);
}

/// The channels of one ABI: opens them and routes the module's events to the
/// channel each one names. The native ABI has one per isolate; every event
/// reaches it through [deliver], its buffer already copied out.
class ChannelCore {
  ChannelCore(this._abi, {this.openGrace = const Duration(seconds: 5)});

  final ChannelAbi _abi;

  /// How much longer than the module's own deadline an open is waited for
  /// before the Dart side gives up on it by itself.
  final Duration openGrace;

  /// The channels whose CLOSED has not come yet, by handle. An entry lives
  /// until then: events for it may arrive until then.
  final Map<int, _CoreChannel> _channels = <int, _CoreChannel>{};

  /// How many channels have not seen their CLOSED - for tests.
  int get liveChannels => _channels.length;

  Future<NoxChannel> open(
    ChannelTarget target, {
    required Uint8List deviceSeed,
    required Uint8List serverKey,
    required Duration timeout,
    Future<void>? cancel,
  }) async {
    // Everything up to the registration below runs before this method first
    // yields, so no event of the new handle can be delivered ahead of it.
    if (deviceSeed.length != 32) throw ArgumentError.value(deviceSeed.length, 'deviceSeed', 'must be 32 bytes');
    if (serverKey.length != 32) throw ArgumentError.value(serverKey.length, 'serverKey', 'must be 32 bytes');
    if (target.host.isEmpty || target.host.contains('\u0000')) throw ArgumentError.value('', 'target', 'needs a host');
    if (target.port < 1 || target.port > 0xFFFF) throw ArgumentError.value(target.port, 'target', 'port out of range');
    if (timeout <= Duration.zero) throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    final handle = _abi.open(
      target is OnionTarget ? 1 : 0,
      target.host,
      target.port,
      deviceSeed,
      serverKey,
      timeout.inMilliseconds.clamp(1, 0xFFFFFFFF),
    );
    if (handle == ChannelReturn.invalidArgument) throw ArgumentError('the channel module refused the arguments');
    if (handle <= 0) throw const ChannelOpenException(ChannelFailure.internal);
    final channel = _CoreChannel(this, handle, Uint8List.fromList(serverKey), timeout + openGrace);
    _channels[handle] = channel;
    cancel?.then((_) => channel._abandon(ChannelFailure.timeout), onError: (Object _) {});
    return channel._opening.future;
  }

  /// One event of the module for [handle]: [data] is the copy of an OPEN's or
  /// a DATA's buffer, [code] the DRAINED ticket or the CLOSED kind. An event
  /// for a handle this core does not hold is dropped.
  void deliver(int handle, int kind, Uint8List? data, int code) {
    final channel = _channels[handle];
    if (channel == null) return;
    try {
      switch (kind) {
        case ChannelEvent.open:
          channel._onOpen(data);
        case ChannelEvent.data:
          if (data != null && data.isNotEmpty) channel._onData(data);
        case ChannelEvent.writable:
          channel._onWritable();
        case ChannelEvent.drained:
          channel._onDrained(code);
        case ChannelEvent.eof:
          channel._onEof();
        case ChannelEvent.closed:
          channel._onClosed(code);
      }
    } on Object {
      // An event must never take the isolate down; the channel's own state
      // says what happened, and a bad one ends in CLOSED like any other.
    }
  }
}

/// One channel of the module.
///
/// The state machine around one handle: the open, the incoming backlog that
/// is held back unacknowledged while nobody reads, the write window, and the
/// flush tickets. Everything is driven by events; none of them is handled
/// before the call that caused it returns.
final class _CoreChannel implements NoxChannel {
  _CoreChannel(this._core, this._handle, this._expectedKey, Duration guard) {
    // A pending open is an error nobody may be listening to by the time it
    // fails - a caller that gave up. Marked handled; whoever does listen
    // still receives it.
    _opening.future.ignore();
    // The module bounds the open itself. This is the Dart side's own guard
    // over a module that never answered: past it, the open is abandoned.
    _guard = Timer(guard, () => _abandon(ChannelFailure.timeout));
  }

  final ChannelCore _core;
  final int _handle;

  /// The key the server must prove; the module checks it, and the OPEN event
  /// is checked against it once more here.
  final Uint8List _expectedKey;

  ChannelAbi get _abi => _core._abi;

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
    final queued = _abi.write(_handle, bytes);
    if (queued < 0) throw StateError('the channel refused the write ($queued)');
    _queued = queued;
    return queued;
  }

  @override
  Future<void> get writable {
    if (_gone) return Future<void>.error(StateError('the channel is closed'));
    if (_queued <= channelWindowBytes) return Future<void>.value();
    // A close fails the wait; one nobody listens to any more is not an
    // unhandled error for that.
    return (_writable ??= (Completer<void>()..future.ignore())).future;
  }

  @override
  Future<void> flush() {
    if (_gone || _closeRequested) return Future<void>.error(StateError('the channel is closed'));
    _ticket = _ticket >= 0x7FFFFFFF ? 1 : _ticket + 1;
    final ticket = _ticket;
    final drained = Completer<void>()..future.ignore();
    _flushes[ticket] = drained;
    if (_abi.flush(_handle, ticket) < 0) {
      _flushes.remove(ticket);
      return Future<void>.error(StateError('the channel is closed'));
    }
    return drained.future;
  }

  @override
  void shutdownWrite() {
    if (_gone || _closeRequested || _writeShut) return;
    _writeShut = true;
    _abi.shutdownWrite(_handle);
  }

  @override
  void close() {
    if (_gone || _closeRequested) return;
    _closeRequested = true;
    _abi.close(_handle);
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
    _abi.ack(_handle, length);
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
    _core._channels.remove(_handle);
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
