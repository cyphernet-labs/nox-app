import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/general/pairing/server_pin.dart';

/// The one HTTP client both transports go through, and the place the server's
/// fingerprint is checked.
///
/// It lives here rather than in either transport because there IS only one
/// decision: commands travel over `wss` and attachment bytes over `https`, to
/// the same machine, judged by the same thirty-two bytes. Two clients would be
/// two chances to get that wrong, and the file half - which carried the bytes
/// in the clear until this feature - is exactly the half that would be
/// forgotten.
///
/// ONE instance for the process, deliberately. `WebSocket.connect` does not
/// close a client handed to it, so a client per connection leaks one on every
/// single reconnect - and the reconnect ladder makes that a steady drip on a
/// flaky link rather than a rare event.
@lazySingleton
class PinnedHttpClient {
  HttpClient? _client;
  String? _fingerprint;

  /// How many certificates this process has refused.
  ///
  /// A counter rather than a flag: a caller records the value before it
  /// connects and compares afterwards, which says "this attempt was refused"
  /// without anything having to be reset. The refusal belongs to the SERVER,
  /// not to one connection, so a concurrent socket and download seeing the same
  /// growth are both reading it correctly.
  int get refusals => _refusals;
  int _refusals = 0;

  /// Which server the next connection will be checked against.
  ///
  /// Set on every start of the live channel rather than once at construction:
  /// this object is a DI singleton and the fingerprint arrives later, when
  /// somebody pairs. Reading it at build time would pin the empty string for
  /// the life of a fresh install, and keep pinning the old server after
  /// somebody paired with a new one.
  void pinTo(String fingerprint) {
    if (_fingerprint == fingerprint) return;
    _fingerprint = fingerprint;
    // A CHANGE of server drops every pooled connection to the old one. The
    // check runs during a handshake, and a kept-alive connection performs
    // none - so without this, re-pairing to a different machine would keep
    // reaching the previous one until its socket happened to time out.
    _discard();
  }

  /// Forgets the server, and hangs up on it.
  ///
  /// After a logout there is nothing this install is entitled to talk to. The
  /// fingerprint alone would not achieve that: connections already open are
  /// never re-checked.
  ///
  /// It hangs up on the HTTP half only. A live WebSocket detaches its socket
  /// from this client at the 101 and is beyond reach here - `NoxSocketClient`
  /// closes it, and `LiveSessionStarter.stop()` does that BEFORE calling this.
  /// That order is the guarantee; this method is not a substitute for it.
  void unpin() {
    _fingerprint = null;
    _discard();
  }

  /// Called after the client underneath has been thrown away.
  ///
  /// Dio's `IOHttpClientAdapter` asks for a client ONCE and caches it, so it
  /// would go on using the closed one and turn every later attachment transfer
  /// into an unexplained failure. [ApiClient] uses this to re-install its
  /// adapter; nothing else needs it.
  void Function()? onDiscarded;

  void _discard() {
    _client?.close(force: true);
    _client = null;
    onDiscarded?.call();
  }

  /// The client. Built once, on first use.
  HttpClient get client => _client ??= _build();

  /// The fingerprint in force. For tests that need to see WHICH server the
  /// connection layer was pointed at, which is otherwise only observable by
  /// standing up a server and dialling it.
  @visibleForTesting
  String? get pinnedFingerprint => _fingerprint;

  HttpClient _build() {
    final client = HttpClient(context: _emptyTrust);
    // The check happens in the connection factory, on the LEAF - see there.
    // This stays as a closed door: with the factory in place nothing
    // legitimate reaches it, and anything that does is refused rather than
    // silently judged by weaker means.
    client.badCertificateCallback = (X509Certificate cert, String host, int port) => false;
    // The factory below ignores proxies, so make that true rather than assume
    // it: a personal server is reached directly, and a proxy the factory
    // quietly skipped would connect somewhere nobody asked for.
    client.findProxy = (Uri uri) => 'DIRECT';
    client.connectionFactory = _connect;
    return client;
  }

  /// An EMPTY trust store, on purpose, and it is load-bearing.
  ///
  /// The platform's roots would let a certificate issued by a public authority
  /// for whatever name the link carries verify on its own, and the pin - the
  /// only thing that checks WHICH key answered - would then never be consulted
  /// at all. Trusting nobody makes every certificate reach it.
  SecurityContext get _emptyTrust => SecurityContext(withTrustedRoots: false);

  /// Opens the connection, and refuses it unless the machine that authenticated
  /// the handshake is the pinned one.
  ///
  /// **The check is on the LEAF, and it has to be.** `badCertificateCallback`
  /// is handed the TOP of the presented chain, not the certificate whose
  /// private key completed the handshake - measured, not assumed. A server
  /// presents whatever chain it likes, so anyone can append the real server's
  /// certificate (public: handed to every client that ever dialled it) above
  /// their own leaf, and a check on the top then hashes the right key while the
  /// session belongs to the wrong one. Reproduced end to end before this was
  /// written; `SecureSocket.peerCertificate` is the leaf, and the same bytes
  /// the Go side pins (`rawCerts[0]`).
  ///
  /// `HttpClient` uses this socket as it is - it does not wrap a direct
  /// connection in TLS a second time - so doing the handshake here is what puts
  /// the leaf within reach. `onBadCertificate` returns true only to let the
  /// handshake finish; the answer is decided below, before a single byte of the
  /// request is written, because `HttpClient` waits on this future.
  Future<ConnectionTask<Socket>> _connect(Uri uri, String? proxyHost, int? proxyPort) async {
    final task = await SecureSocket.startConnect(
      uri.host,
      uri.port,
      context: _emptyTrust,
      onBadCertificate: (_) => true,
      // The server offers exactly this, and the WebSocket upgrade both
      // transports share does not exist over h2.
      supportedProtocols: const <String>['http/1.1'],
    );
    return ConnectionTask.fromSocket<SecureSocket>(
      task.socket.then((socket) {
        // Read at handshake time, never captured: this client outlives
        // pairing, re-pairing and logout.
        if (ServerPin.matches(socket.peerCertificate?.der, _fingerprint)) return socket;
        _refusals++;
        socket.destroy();
        throw const HandshakeException('the server presented a key the pairing link did not name');
      }),
      task.cancel,
    );
  }
}
