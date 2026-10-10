import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/remote/channel/channel_socket.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_tor/channel.dart';

/// The HTTP clients both transports go through, and the one place a
/// connection to the server is opened (phase 044).
///
/// Every connection - the socket's `wss` and the attachment bytes' `https` -
/// is a channel of the native module: transport, then TLS 1.3, then the
/// Eidolon check that the machine answering proves the key the pairing link
/// named, and that this device proves its own. Nothing here sees a
/// certificate, and nothing needs to: the certificate is technical, and who is
/// on the other end is decided below TLS-the-encryption, by the check bound to
/// this very connection.
///
/// ONE client per transport for the process, deliberately. `WebSocket.connect`
/// does not close a client handed to it, so a client per connection would leak
/// one on every rung of the reconnect ladder. And not one for both (phase
/// 043): Dio writes its connect timeout onto the client it is given, on every
/// request, and the socket dials through that same setting - so a transfer at
/// home would cut the socket's next dial through Tor at Dio's 30 s.
@LazySingleton(env: [Environment.dev])
class ChannelHttpClient {
  ChannelHttpClient(this._api);

  final NoxChannelApi _api;

  HttpClient? _client;
  HttpClient? _transferClient;
  _Binding? _binding;

  /// How long one open may take, transport, TLS and the check together, when
  /// nothing above cuts it sooner (research decision 20): the path's budget.
  /// Through Tor an onion connect with its hedge fits the same 45 s the bridge
  /// had.
  static const Duration directOpenTimeout = Duration(seconds: 30);
  static const Duration onionOpenTimeout = Duration(seconds: 45);

  /// Which server the next connection must prove, and which device it proves.
  ///
  /// Set on every start of the live channel rather than once at construction:
  /// this object is a DI singleton and both keys arrive later, when somebody
  /// pairs. Copies are kept; the caller's bytes stay the caller's.
  void bind({required Uint8List serverKey, required Uint8List deviceSeed}) {
    if (serverKey.length != 32) throw ArgumentError.value(serverKey.length, 'serverKey', 'must be 32 bytes');
    if (deviceSeed.length != 32) throw ArgumentError.value(deviceSeed.length, 'deviceSeed', 'must be 32 bytes');
    final current = _binding;
    if (current != null && listEquals(current.serverKey, serverKey) && listEquals(current.deviceSeed, deviceSeed)) return;
    current?.wipe();
    _binding = _Binding(Uint8List.fromList(serverKey), Uint8List.fromList(deviceSeed));
    // A CHANGE drops every pooled connection: each was verified for the keys
    // it was opened with, and a kept-alive connection is never verified again
    // - re-pairing would otherwise keep reaching the previous machine until
    // its connection happened to time out.
    _discard();
  }

  /// Forgets both keys, and hangs up.
  ///
  /// After a logout there is nothing this install is entitled to talk to;
  /// every later open fails at once. It hangs up on the HTTP half only: a live
  /// WebSocket has left this client at the 101, and `NoxSocketClient` closes
  /// it - `LiveSessionStarter.stop()` does that BEFORE calling this. That order
  /// is the guarantee; this method is not a substitute for it.
  void unbind() {
    _binding?.wipe();
    _binding = null;
    _discard();
  }

  /// Called after the clients underneath have been thrown away. Dio's
  /// `IOHttpClientAdapter` asks for a client ONCE and caches it, so it would
  /// go on using the closed one; [ApiClient] re-installs its adapter here.
  void Function()? onDiscarded;

  void _discard() {
    // Force: an open still under way is cancelled too, and the cancel reaches
    // the module (see [_connect]).
    _client?.close(force: true);
    _client = null;
    _transferClient?.close(force: true);
    _transferClient = null;
    onDiscarded?.call();
  }

  /// The socket's client. Built once, on first use.
  HttpClient get client => _client ??= _build();

  /// The client for attachment bytes: opened exactly as the socket's, and apart
  /// from it only so that what Dio sets on it stays on it.
  HttpClient get transferClient => _transferClient ??= _build();

  /// The server key in force, for tests that need to see WHICH server the
  /// connection layer was pointed at.
  @visibleForTesting
  Uint8List? get boundServerKey => _binding?.serverKey;

  HttpClient _build() {
    final client = HttpClient();
    // The factory below ignores proxies; make that true rather than assume
    // it. A personal server is reached directly, and a proxy the factory
    // quietly skipped would connect somewhere nobody asked for.
    client.findProxy = (Uri uri) => 'DIRECT';
    // Never consulted: the factory hands over a socket that is already
    // encrypted, and `HttpClient` adds no TLS of its own to a direct one. A
    // closed door all the same.
    client.badCertificateCallback = (X509Certificate cert, String host, int port) => false;
    client.connectionFactory = _connect;
    // Every connection through the onion service is a stream on one Tor
    // circuit, and the server's tor closes a circuit that opens more than 16
    // streams at once (`HiddenServiceMaxStreams 16` with
    // `HiddenServiceMaxStreamsCloseCircuit 1`) - the command socket with it.
    // The socket needs one connection and the transfers a few; a request past
    // the cap waits for a free one rather than opening the seventeenth.
    client.maxConnectionsPerHost = maxConnectionsPerHost;
    return client;
  }

  /// The most connections each client keeps to the server at once: well under
  /// the 16 streams a Tor circuit to the onion service may hold, together with
  /// the other client's.
  static const int maxConnectionsPerHost = 6;

  /// Where [uri] is opened: the onion service for an onion host, the address
  /// itself otherwise.
  @visibleForTesting
  static ChannelTarget targetFor(Uri uri) {
    final host = uri.host;
    if (host.toLowerCase().endsWith('.onion')) return OnionTarget(host);
    return DirectTarget(host, uri.hasPort ? uri.port : 443);
  }

  /// Opens the channel for one connection of `HttpClient`.
  ///
  /// The task's cancel reaches the module: `HttpClient` cancels a connect it
  /// has timed out (`connectionTimeout`) or closed under (`close(force:)`),
  /// and then never looks at the socket again - an open left running would
  /// finish into a connection nobody holds. A channel that opens after the
  /// cancel anyway is closed on arrival.
  Future<ConnectionTask<Socket>> _connect(Uri uri, String? proxyHost, int? proxyPort) async {
    final binding = _binding;
    // Read at connect time, never captured: this client outlives pairing,
    // re-pairing and logout. Without keys there is no server to prove.
    if (binding == null) throw const SocketException('the channel is not bound to a server');
    final target = targetFor(uri);
    final watch = Stopwatch()..start();
    final cancelled = Completer<void>();
    final opening = _api.open(
      target,
      deviceSeed: binding.deviceSeed,
      serverKey: binding.serverKey,
      timeout: target is OnionTarget ? onionOpenTimeout : directOpenTimeout,
      cancel: cancelled.future,
    );
    final socket = opening.then<Socket>(
      (channel) {
        if (cancelled.isCompleted) {
          channel.close();
          _log(target, watch, 'cancelled');
          throw const SocketException('the connection was cancelled');
        }
        _log(target, watch, 'open');
        return ChannelSocket(channel, remoteAddress: InternetAddress.tryParse(target.host), remotePort: target.port);
      },
      onError: (Object error, StackTrace stack) {
        _log(target, watch, cancelled.isCompleted ? 'cancelled' : _kindOf(error));
        Error.throwWithStackTrace(error, stack);
      },
    );
    return ConnectionTask.fromSocket(socket, () {
      if (!cancelled.isCompleted) cancelled.complete();
    });
  }

  /// One line per open: which path, how long, how it ended. Never a key, a
  /// seed, a token or an onion host - the path's kind is all it names.
  void _log(ChannelTarget target, Stopwatch watch, String outcome) {
    final path = target is OnionTarget ? 'onion' : 'direct';
    logRepository.debug(target: this, message: 'channel: $path $outcome after ${watch.elapsedMilliseconds} ms');
  }

  static String _kindOf(Object error) => switch (error) {
    ChannelOpenException(:final failure) => 'failed (${failure.name})',
    _ => 'failed (${error.runtimeType})',
  };
}

class _Binding {
  _Binding(this.serverKey, this.deviceSeed);

  final Uint8List serverKey;
  final Uint8List deviceSeed;

  /// The seed is this device's private key; a binding that is let go of does
  /// not leave it in memory.
  void wipe() => deviceSeed.fillRange(0, deviceSeed.length, 0);
}
