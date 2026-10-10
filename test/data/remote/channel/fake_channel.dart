import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:nox_tor/channel.dart';

/// A channel scripted by the test: what the server sends, how full the queue
/// is, when a flush drains, how the channel ends. No module, no network.
class FakeNoxChannel implements NoxChannel {
  final StreamController<Uint8List> _incoming = StreamController<Uint8List>();
  final Completer<ChannelFailure?> _closed = Completer<ChannelFailure?>();

  /// Everything written, chunk by chunk.
  final List<Uint8List> written = <Uint8List>[];

  /// What the queue holds; every write adds to it, [drain] empties it.
  int queued = 0;

  Completer<void>? _writable;
  final List<Completer<void>> _flushes = <Completer<void>>[];

  bool shutDown = false;
  int closeCalls = 0;

  /// Whether the reader of [incoming] has paused it - what stops the module
  /// acknowledging, and so reading.
  bool get readerPaused => _incoming.isPaused;

  bool get isGone => _closed.isCompleted;

  List<int> get writtenBytes => [for (final chunk in written) ...chunk];

  int get pendingFlushes => _flushes.length;

  /// The server sends [bytes].
  void receive(List<int> bytes) => _incoming.add(Uint8List.fromList(bytes));

  /// The server ends its side.
  void eof() => _incoming.close();

  /// The queue drains to nothing: a writer held back may go on, and every
  /// flush asked for so far completes.
  void drain() {
    queued = 0;
    final waiting = _writable;
    _writable = null;
    waiting?.complete();
    for (final flush in _flushes) {
      flush.complete();
    }
    _flushes.clear();
  }

  /// The channel fails with [failure] after it opened.
  void fail(ChannelFailure failure) {
    if (_closed.isCompleted) return;
    if (!_incoming.isClosed) {
      _incoming.addError(ChannelLostException(failure));
      _incoming.close();
    }
    _end(failure);
  }

  void _end(ChannelFailure? failure) {
    if (_closed.isCompleted) return;
    final error = StateError('the channel is closed');
    _writable?.completeError(error);
    _writable = null;
    for (final flush in _flushes) {
      flush.completeError(error);
    }
    _flushes.clear();
    _closed.complete(failure);
  }

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  @override
  int write(Uint8List bytes) {
    if (_closed.isCompleted || shutDown) throw StateError('the channel is closed');
    written.add(Uint8List.fromList(bytes));
    queued += bytes.length;
    return queued;
  }

  @override
  Future<void> get writable {
    if (_closed.isCompleted) return Future<void>.error(StateError('the channel is closed'));
    if (queued <= channelWindowBytes) return Future<void>.value();
    return (_writable ??= Completer<void>()).future;
  }

  @override
  Future<void> flush() {
    if (_closed.isCompleted) return Future<void>.error(StateError('the channel is closed'));
    final flush = Completer<void>();
    _flushes.add(flush);
    return flush.future;
  }

  @override
  void shutdownWrite() => shutDown = true;

  @override
  void close() {
    closeCalls++;
    if (!_incoming.isClosed) _incoming.close();
    _end(null);
  }

  @override
  Future<ChannelFailure?> get closed => _closed.future;
}

/// One call to [NoxChannelApi.open], as the test saw it.
class OpenCall {
  OpenCall(this.target, this.deviceSeed, this.serverKey, this.timeout, this.cancel);

  final ChannelTarget target;
  final Uint8List deviceSeed;
  final Uint8List serverKey;
  final Duration timeout;
  final Future<void>? cancel;
  final Completer<NoxChannel> result = Completer<NoxChannel>();

  bool get cancelled => _cancelled;
  bool _cancelled = false;
}

/// Records every open and lets the test answer it - at once, later, or never.
class ScriptedChannelApi implements NoxChannelApi {
  final List<OpenCall> calls = <OpenCall>[];

  /// Answers each open as it comes; null leaves it to the test.
  FutureOr<NoxChannel> Function(OpenCall call)? answer;

  @override
  Future<NoxChannel> open(
    ChannelTarget target, {
    required Uint8List deviceSeed,
    required Uint8List serverKey,
    required Duration timeout,
    Future<void>? cancel,
  }) {
    final call = OpenCall(target, Uint8List.fromList(deviceSeed), Uint8List.fromList(serverKey), timeout, cancel);
    calls.add(call);
    cancel?.then((_) => call._cancelled = true);
    final answer = this.answer;
    if (answer != null) {
      Future<NoxChannel>.sync(() => answer(call)).then(call.result.complete, onError: call.result.completeError);
    }
    return call.result.future;
  }
}

/// A channel over a real loopback TCP connection to a plain server, so the
/// HTTP and WebSocket stacks can be run over [NoxChannel] end to end - the
/// bytes they write reach a real `HttpServer`, and its answers come back.
class LoopbackChannel implements NoxChannel {
  LoopbackChannel._(this._socket) {
    _socket.done.then((_) => _end(null), onError: (Object _) => _end(ChannelFailure.network));
  }

  static Future<LoopbackChannel> connect(int port) async => LoopbackChannel._(await Socket.connect(InternetAddress.loopbackIPv4, port));

  final Socket _socket;
  final Completer<ChannelFailure?> _closed = Completer<ChannelFailure?>();
  bool _shut = false;
  int closeCalls = 0;

  void _end(ChannelFailure? failure) {
    if (!_closed.isCompleted) _closed.complete(failure);
  }

  @override
  Stream<Uint8List> get incoming => _socket;

  @override
  int write(Uint8List bytes) {
    if (_closed.isCompleted || _shut) throw StateError('the channel is closed');
    _socket.add(bytes);
    return 0;
  }

  @override
  Future<void> get writable => Future<void>.value();

  @override
  Future<void> flush() => _socket.flush();

  @override
  void shutdownWrite() {
    if (_shut) return;
    _shut = true;
    _socket.close().ignore();
  }

  @override
  void close() {
    closeCalls++;
    _socket.destroy();
    _end(null);
  }

  @override
  Future<ChannelFailure?> get closed => _closed.future;
}

/// Opens every channel as a loopback connection to [port], whatever the
/// target names - the server under test stands in for the one at that
/// address. Without a [port], each channel goes to the loopback port its
/// direct target names - for tests that move between servers by address.
class LoopbackChannelApi implements NoxChannelApi {
  LoopbackChannelApi([this.port]);

  final int? port;
  final List<ChannelTarget> targets = <ChannelTarget>[];
  final List<LoopbackChannel> opened = <LoopbackChannel>[];

  @override
  Future<NoxChannel> open(
    ChannelTarget target, {
    required Uint8List deviceSeed,
    required Uint8List serverKey,
    required Duration timeout,
    Future<void>? cancel,
  }) async {
    targets.add(target);
    final to = port ?? (target is DirectTarget ? target.port : null);
    if (to == null) throw const ChannelOpenException(ChannelFailure.torNotReady);
    final LoopbackChannel channel;
    try {
      channel = await LoopbackChannel.connect(to);
    } on SocketException {
      throw const ChannelOpenException(ChannelFailure.network);
    }
    opened.add(channel);
    return channel;
  }
}
