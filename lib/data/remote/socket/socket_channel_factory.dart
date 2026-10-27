import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/remote/channel/channel_http_client.dart';
import 'package:nox_app/data/remote/socket/socket_target_provider.dart';
import 'package:web_socket_channel/io.dart';

/// The narrow port the transport actually needs: frames in, frames out, close.
///
/// Deliberately NOT `WebSocketChannel` itself — depending on the package's type
/// would force every test to construct a real channel. With this port a fake is
/// three methods, so correlation, backoff and phase transitions are testable
/// without a server and without the network.
abstract class SocketConnection {
  Stream<dynamic> get frames;
  void add(String frame);
  Future<void> close();
}

/// Opens a [SocketConnection].
abstract class SocketChannelFactory {
  SocketConnection connect(Uri url);
}

/// Real sockets, with keepalive wired in at the platform level.
///
/// [IOWebSocketChannel] is used rather than `WebSocketChannel.connect` because
/// only it exposes `pingInterval`, and because only it takes a client of ours -
/// which is how the socket runs over the verified channel of the native module
/// at all (phase 044). NOX ships on five IO platforms (web is out of scope), so
/// binding to the IO implementation costs nothing.
///
/// A channel that would not open reaches the frames stream as the stream's
/// first and only event, its kind inside the WebSocket's envelope - the
/// socket client reads it out with `channelFailureOf`.
@LazySingleton(as: SocketChannelFactory, env: [Environment.dev])
class WebSocketChannelFactory implements SocketChannelFactory {
  WebSocketChannelFactory(this._channels);

  /// Contract §9: ~25s, because cellular NATs drop an idle flow at ~30s. A
  /// missed pong surfaces as a socket close, which is the disconnect signal.
  static const Duration pingInterval = Duration(seconds: 25);

  /// How long one dial may take (phase 040).
  static const Duration directConnectTimeout = Duration(seconds: 10);
  static const Duration onionConnectTimeout = Duration(seconds: 45);

  final ChannelHttpClient _channels;

  @override
  SocketConnection connect(Uri url) {
    final timeout = isOnionUrl(url) ? onionConnectTimeout : directConnectTimeout;
    // The SHARED client, never a fresh one: `WebSocket.connect` does not close
    // a client passed to it, so one per connection would leak on every rung of
    // the reconnect ladder.
    //
    // Its connect timeout is set to the dial's own, for every dial: the
    // channel's timeout alone only abandons the WAIT, and the open would run
    // on in the module and finish into a connection nobody holds. The pool
    // cancels its connect at that moment, and the cancel reaches the module.
    final client = _channels.client..connectionTimeout = timeout;
    return _IoSocketConnection(
      IOWebSocketChannel.connect(
        url,
        pingInterval: pingInterval,
        // Bounded, which it never was: a dial that hangs held the reconnect
        // ladder with it. Longer through Tor, where one keyed connection
        // fetches the onion service's descriptor anew and sometimes stalls
        // (phase 040, research decision 5).
        connectTimeout: timeout,
        customClient: client,
      ),
    );
  }
}

class _IoSocketConnection implements SocketConnection {
  _IoSocketConnection(this._channel) {
    // The app learns that a connection failed from the frames stream, which is
    // the one place that also carries frames. The error is handled here
    // because the channel completes `ready` with it as well, and an error on a
    // future with no listener is an unhandled zone error - raised on EVERY rung
    // of the reconnect ladder while offline, and on every refused server key.
    // The failure itself is still reported on the frames stream, once.
    _channel.ready.then<void>((_) {
      if (_closed) return;
      _opened = true;
      for (final frame in _held) {
        _channel.sink.add(frame);
      }
      _held.clear();
    }, onError: (Object _) => _held.clear());
  }

  final IOWebSocketChannel _channel;

  /// Frames handed over before the connection opened, held HERE rather than in
  /// the channel. The channel's own buffer is flushed once the upgrade
  /// completes even after a close, so a frame given to a dial the app had
  /// already abandoned - a pairing token above all - would still reach the
  /// server, behind the app's back. And none is ever written before the
  /// channel has verified the server's key: a connection that fails that check
  /// never becomes ready, and its held frames are dropped.
  final List<String> _held = <String>[];
  bool _opened = false;
  bool _closed = false;

  @override
  Stream<dynamic> get frames => _channel.stream;

  @override
  void add(String frame) {
    if (_closed) return;
    if (_opened) {
      _channel.sink.add(frame);
    } else {
      _held.add(frame);
    }
  }

  /// Returns at once while the dial is still under way. The channel's close
  /// follows the dial, and one that then fails never completes it: awaited,
  /// that wedged the reconnect it was part of, a logout half-way through its
  /// wipe, and a failed sign-in's rollback. A dial that does complete is
  /// closed by this same call, with nothing sent.
  @override
  Future<void> close() {
    _closed = true;
    _held.clear();
    final closing = _channel.sink.close();
    if (_opened) return closing;
    closing.ignore();
    return Future<void>.value();
  }
}

/// Thrown when the socket cannot carry a command: no connection, or no reply
/// within the contract's send timeout.
class SocketUnavailableException implements Exception {
  const SocketUnavailableException(this.reason);
  final String reason;
  @override
  String toString() => 'SocketUnavailableException: $reason';
}
