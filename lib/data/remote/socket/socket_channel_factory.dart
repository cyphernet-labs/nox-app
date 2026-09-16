import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/remote/pinned_http_client.dart';
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
/// which is how the socket is checked against the server's fingerprint at all.
/// NOX ships on five IO platforms (web is out of scope), so binding to the IO
/// implementation costs nothing.
@LazySingleton(as: SocketChannelFactory, env: [Environment.dev])
class WebSocketChannelFactory implements SocketChannelFactory {
  WebSocketChannelFactory(this._pinned);

  /// Contract §9: ~25s, because cellular NATs drop an idle flow at ~30s. A
  /// missed pong surfaces as a socket close, which is the disconnect signal.
  static const Duration pingInterval = Duration(seconds: 25);

  final PinnedHttpClient _pinned;

  @override
  SocketConnection connect(Uri url) {
    // The SHARED client, never a fresh one: `WebSocket.connect` does not close
    // a client passed to it, so one per connection would leak on every rung of
    // the reconnect ladder.
    //
    // The refusal count is read BEFORE the attempt and compared after it
    // fails. The certificate callback cannot throw anything anybody upstream
    // would recognise - it returns a bool from inside the TLS stack, and what
    // comes out is an ordinary handshake failure indistinguishable from a
    // server that is simply down. Without this, a refused pin would climb the
    // reconnect ladder for ever while the screen blamed the network.
    final before = _pinned.refusals;
    return _IoSocketConnection(
      IOWebSocketChannel.connect(url, pingInterval: pingInterval, customClient: _pinned.client),
      () => _pinned.refusals > before,
    );
  }
}

class _IoSocketConnection implements SocketConnection {
  _IoSocketConnection(this._channel, this._wasRefused);

  final IOWebSocketChannel _channel;

  /// Whether the pin refused a certificate since this connection was started.
  final bool Function() _wasRefused;

  @override
  Stream<dynamic> get frames => _channel.stream.transform(
    StreamTransformer<dynamic, dynamic>.fromHandlers(
      handleError: (Object error, StackTrace stack, EventSink<dynamic> sink) {
        sink.addError(_wasRefused() ? const ServerPinRefusedException() : error, stack);
      },
    ),
  );

  @override
  void add(String frame) => _channel.sink.add(frame);

  @override
  Future<void> close() => _channel.sink.close();
}

/// The machine at the paired address presented a key the pairing link did not
/// name.
///
/// Its own type, not a message inside a general transport failure: the whole
/// point is that it must be told apart from "the network is down". Retrying
/// cannot help, and nothing here may take the path that ends in a forced
/// logout - that path wipes the device, which would make presenting a
/// certificate a way to erase somebody's messages.
class ServerPinRefusedException implements Exception {
  const ServerPinRefusedException();

  @override
  String toString() => 'ServerPinRefusedException: the server presented a key the pairing link did not name';
}

/// Thrown when the socket cannot carry a command: no connection, or no reply
/// within the contract's send timeout.
class SocketUnavailableException implements Exception {
  const SocketUnavailableException(this.reason);
  final String reason;
  @override
  String toString() => 'SocketUnavailableException: $reason';
}
