import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nox_tor/channel.dart';

/// A `dart:io` [Socket] over a verified [NoxChannel] (phase 044).
///
/// What lets `HttpClient` - and through it `WebSocket` and Dio - run over the
/// channel without knowing it exists: a connection factory hands this over in
/// place of a TCP socket, and a direct connection is used exactly as given -
/// `HttpClient` does not wrap it in TLS of its own (that happens only on the
/// way through a proxy). The TLS is the module's, below this.
///
/// Backpressure both ways. Incoming: pausing this stream pauses the channel's,
/// and the module stops reading after one unacknowledged window. Outgoing:
/// `HttpClient` writes a body through [addStream] and pauses its own source
/// when asked to, so [addStream] pauses the stream it consumes while more than
/// a window is queued - an upload of a large file never sits in memory whole.
///
/// The addresses are placeholders: the transport belongs to the module, and
/// none of it is visible here. [remoteAddress] is the dialled IP when the
/// target named one and `0.0.0.0` otherwise - a name, or an onion address,
/// which is never put where it could be read back; [address] is `0.0.0.0`
/// and [port] 0.
class ChannelSocket extends Stream<Uint8List> implements Socket {
  ChannelSocket(this._channel, {InternetAddress? remoteAddress, this.remotePort = 0})
    : remoteAddress = remoteAddress ?? InternetAddress.anyIPv4 {
    // Whoever holds the socket may never ask for [done]; an error there is
    // reported to those who do.
    _done.future.ignore();
    unawaited(_channel.closed.then(_onChannelClosed));
  }

  final NoxChannel _channel;

  @override
  final InternetAddress remoteAddress;

  @override
  final int remotePort;

  @override
  InternetAddress get address => InternetAddress.anyIPv4;

  @override
  int get port => 0;

  @override
  Encoding encoding = utf8;

  final Completer<Object?> _done = Completer<Object?>();

  /// [close] was called: no more writing, by contract.
  bool _closed = false;

  /// [destroy] was called, or the channel is gone.
  bool _destroyed = false;

  /// The channel closed under us.
  bool _gone = false;

  /// The read side is finished: done, or nobody reads any more.
  bool _readDone = false;

  /// The write side is finished: closed or destroyed.
  bool _writeDone = false;

  /// The channel has been let go of, by [_release] or [destroy].
  bool _released = false;

  StreamController<Uint8List>? _reads;
  StreamSubscription<Uint8List>? _readSub;

  /// The [addStream] under way, if any.
  StreamSubscription<List<int>>? _boundSub;
  Completer<void>? _bound;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final reads = _reads ??= StreamController<Uint8List>(
      sync: true,
      onListen: _startReading,
      onPause: () => _readSub?.pause(),
      onResume: () => _readSub?.resume(),
      onCancel: _stopReading,
    );
    return reads.stream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  void _startReading() {
    final reads = _reads!;
    _readSub = _channel.incoming.listen(
      reads.add,
      // The type the HTTP stack reads a broken connection by: anything else
      // it rethrows as unhandled.
      onError: (Object error, StackTrace stack) => reads.addError(_socketError(error), stack),
      onDone: () {
        _readDone = true;
        unawaited(reads.close());
        _release();
      },
    );
  }

  Future<void> _stopReading() async {
    _readDone = true;
    final sub = _readSub;
    _readSub = null;
    _release();
    await sub?.cancel();
  }

  @override
  void add(List<int> data) {
    if (_closed) throw StateError('StreamSink is closed');
    if (_bound != null) throw StateError('StreamSink is bound to a stream');
    _write(data);
  }

  /// Queues [data] and returns the size of the queue after it; 0 once there
  /// is nowhere to write - what went wrong is reported where it is read, as
  /// a socket that has been reset reports it.
  int _write(List<int> data) {
    if (_destroyed || data.isEmpty) return 0;
    try {
      return _channel.write(data is Uint8List ? data : Uint8List.fromList(data));
    } on StateError {
      return 0;
    }
  }

  @override
  void write(Object? object) {
    final string = '$object';
    if (string.isEmpty) return;
    add(encoding.encode(string));
  }

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {
    final iterator = objects.iterator;
    if (!iterator.moveNext()) return;
    if (separator.isEmpty) {
      do {
        write(iterator.current);
      } while (iterator.moveNext());
    } else {
      write(iterator.current);
      while (iterator.moveNext()) {
        write(separator);
        write(iterator.current);
      }
    }
  }

  @override
  void writeln([Object? object = '']) {
    write(object);
    write('\n');
  }

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  /// Writes everything [stream] gives, pausing it while more than a window is
  /// queued and resuming it once the channel has room again.
  @override
  Future<dynamic> addStream(Stream<List<int>> stream) {
    if (_closed) throw StateError('StreamSink is closed');
    if (_bound != null) throw StateError('StreamSink is already bound to a stream');
    final bound = _bound = Completer<void>();
    if (_destroyed) {
      _bound = null;
      stream.listen(null).cancel().ignore();
      return Future<dynamic>.value(this);
    }
    late final StreamSubscription<List<int>> sub;
    sub = _boundSub = stream.listen(
      (chunk) {
        if (_write(chunk) > channelWindowBytes) {
          // Never an error: a channel that closed meanwhile resumes the
          // source into writes that go nowhere, and its own close ends this
          // stream at once.
          sub.pause(_channel.writable.catchError((Object _) {}));
        }
      },
      onError: (Object error, StackTrace stack) => _endBound(error: error, stack: stack),
      onDone: _endBound,
      cancelOnError: true,
    );
    return bound.future.then((_) => this);
  }

  /// Ends the [addStream] under way - its source finished, failed, or the
  /// socket is going away under it.
  void _endBound({Object? error, StackTrace? stack, bool cancel = false}) {
    final bound = _bound;
    if (bound == null) return;
    final sub = _boundSub;
    _bound = null;
    _boundSub = null;
    if (cancel) sub?.cancel().ignore();
    if (bound.isCompleted) return;
    if (error != null) {
      bound.completeError(error, stack);
    } else {
      bound.complete();
    }
  }

  @override
  Future<dynamic> flush() {
    if (_bound != null) throw StateError('StreamSink is bound to a stream');
    if (_destroyed) return Future<dynamic>.value(this);
    return _channel.flush().then<dynamic>(
      (_) => this,
      onError: (Object error, StackTrace stack) {
        Error.throwWithStackTrace(_socketError(error), stack);
      },
    );
  }

  /// Ends writing: the module sends what is queued, then TLS `close_notify`.
  /// Reading goes on until the server ends its side.
  @override
  Future<dynamic> close() {
    if (_bound != null) throw StateError('StreamSink is bound to a stream');
    if (!_closed) {
      _closed = true;
      if (!_destroyed) _channel.shutdownWrite();
      _writeDone = true;
      _release();
      if (!_done.isCompleted) _done.complete(this);
    }
    return _done.future;
  }

  /// Ends the connection at once, both ways.
  @override
  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    _writeDone = true;
    _released = true;
    _channel.close();
    _endBound(cancel: true);
    if (!_done.isCompleted) _done.complete(this);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (_closed) throw StateError('StreamSink is closed');
    if (_bound != null) throw StateError('StreamSink is bound to a stream');
    if (!_done.isCompleted) _done.completeError(error, stackTrace);
    destroy();
  }

  @override
  Future<dynamic> get done => _done.future;

  /// Nothing to set: the transport, and the TLS above it, are the module's.
  @override
  bool setOption(SocketOption option, bool enabled) => true;

  /// The module has no raw options to read; the answer is empty.
  @override
  Uint8List getRawOption(RawSocketOption option) => Uint8List(0);

  @override
  void setRawOption(RawSocketOption option) {}

  /// Lets the module drop the channel once both directions are finished: the
  /// server ended its side and this side ended its own, or nobody reads.
  void _release() {
    if (!_writeDone || !_readDone || _gone || _released) return;
    _released = true;
    _channel.close();
  }

  void _onChannelClosed(ChannelFailure? failure) {
    _gone = true;
    _destroyed = true;
    _writeDone = true;
    // A body still being written has nowhere to go: its source stops now,
    // rather than being read to the end - a large file, from disk - into a
    // channel that is gone.
    if (_bound != null) {
      _endBound(error: SocketException('the channel closed (${failure?.name ?? 'normally'})'), cancel: true);
    }
    if (_done.isCompleted) return;
    if (failure == null) {
      _done.complete(this);
    } else {
      _done.completeError(SocketException('the channel failed (${failure.name})'));
    }
  }

  static SocketException _socketError(Object error) => switch (error) {
    final SocketException e => e,
    ChannelLostException(:final failure) => SocketException('the channel failed (${failure.name})'),
    _ => SocketException('the channel failed (${error.runtimeType})'),
  };
}
