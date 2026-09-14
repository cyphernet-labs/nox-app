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
    // callback runs during a handshake, and a kept-alive connection performs
    // none - so without this, re-pairing to a different machine would keep
    // reaching the previous one until its socket happened to time out.
    _discard();
  }

  /// Forgets the server, and hangs up on it.
  ///
  /// After a logout there is nothing this install is entitled to talk to. The
  /// fingerprint alone would not achieve that: connections already open are
  /// never re-checked.
  void unpin() {
    _fingerprint = null;
    _discard();
  }

  void _discard() {
    _client?.close(force: true);
    _client = null;
  }

  /// The client. Built once, on first use.
  HttpClient get client => _client ??= _build();

  /// The fingerprint in force. For tests that need to see WHICH server the
  /// connection layer was pointed at, which is otherwise only observable by
  /// standing up a server and dialling it.
  @visibleForTesting
  String? get pinnedFingerprint => _fingerprint;

  HttpClient _build() {
    // An EMPTY trust store, on purpose, and it is load-bearing.
    //
    // badCertificateCallback only runs when the built-in verification has
    // already failed. With the platform's roots in place, a certificate issued
    // by a public authority for whatever name the link carries would verify -
    // and the callback below, the only thing that checks WHICH key answered,
    // would never be consulted at all. Trusting nobody makes every certificate
    // reach the pin.
    final client = HttpClient(context: SecurityContext(withTrustedRoots: false));
    // What arrives here is the TOP of the chain the server presented, not
    // necessarily its leaf - measured, not assumed. Our server presents exactly
    // one self-signed certificate, so the two are the same thing and the key
    // below is the server's own. A server presenting a real chain could not be
    // pinned through this callback at all; nothing in this product builds one.
    client.badCertificateCallback = (X509Certificate cert, String host, int port) {
      // The field is read here, at handshake time, and never captured into this
      // closure: the client outlives pairing, re-pairing and logout.
      if (ServerPin.matches(cert.der, _fingerprint)) return true;
      _refusals++;
      return false;
    };
    return client;
  }
}
