import 'package:injectable/injectable.dart';
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
/// only it exposes `pingInterval`. NOX ships on five IO platforms (web is out
/// of scope), so binding to the IO implementation costs nothing.
@LazySingleton(as: SocketChannelFactory, env: [Environment.dev])
class WebSocketChannelFactory implements SocketChannelFactory {
  /// Contract §9: ~25s, because cellular NATs drop an idle flow at ~30s. A
  /// missed pong surfaces as a socket close, which is the disconnect signal.
  static const Duration pingInterval = Duration(seconds: 25);

  @override
  SocketConnection connect(Uri url) => _IoSocketConnection(IOWebSocketChannel.connect(url, pingInterval: pingInterval));
}

class _IoSocketConnection implements SocketConnection {
  _IoSocketConnection(this._channel);

  final IOWebSocketChannel _channel;

  @override
  Stream<dynamic> get frames => _channel.stream;

  @override
  void add(String frame) => _channel.sink.add(frame);

  @override
  Future<void> close() => _channel.sink.close();
}

/// Thrown when the socket cannot carry a command: no connection, or no reply
/// within the contract's send timeout.
class SocketUnavailableException implements Exception {
  const SocketUnavailableException(this.reason);
  final String reason;
  @override
  String toString() => 'SocketUnavailableException: $reason';
}
