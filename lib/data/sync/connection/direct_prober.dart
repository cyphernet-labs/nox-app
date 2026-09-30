import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:nox_app/general/pairing/server_pin.dart';

/// What one round of direct attempts found (phase 040).
class DirectProbeResult {
  const DirectProbeResult({this.address, this.notHome = const <String>[]});

  /// The first candidate that answered with the right key and a healthy
  /// `/health`; null when none did within the budget.
  final String? address;

  /// Candidates that answered with ANOTHER key. They do not lead home right
  /// now (FR-005) - an address is a place, and on another network the same one
  /// is somebody else's machine. Never a reason to call the server foreign.
  final List<String> notHome;
}

/// Tries the server's direct addresses (phase 040).
abstract class DirectProber {
  /// Tries [candidates] in order of preference and returns the first that
  /// answers as the server [fingerprint] names.
  Future<DirectProbeResult> probe(List<String> candidates, {required String fingerprint});
}

/// Over connections of its own, never the transport's client.
///
/// The transport learns of a refused pin from a counter on its shared client;
/// a probe running beside a socket dial would have its refusal blamed on the
/// socket (research decision 8). A probe owns its sockets, so each refusal
/// belongs to exactly one address.
///
/// The check is the transport's: TLS with nobody trusted, then the LEAF's key
/// against the fingerprint - see `PinnedHttpClient` for why it must be the
/// leaf. A probe only says which address to dial; the socket that follows is
/// checked again on its own handshake.
@LazySingleton(as: DirectProber, env: [Environment.dev])
class TlsDirectProber implements DirectProber {
  /// One address may take this long, handshake and `/health` together.
  static const Duration attemptTimeout = Duration(milliseconds: 2500);

  /// The first candidate goes alone for this long - the one that answered last
  /// time usually answers again - and then the rest go together.
  static const Duration stagger = Duration(milliseconds: 300);

  /// The whole round. Tor starts no later than this after the attempt does
  /// (FR-002).
  static const Duration budget = Duration(seconds: 5);

  @override
  Future<DirectProbeResult> probe(List<String> candidates, {required String fingerprint}) async {
    if (candidates.isEmpty || fingerprint.isEmpty) return const DirectProbeResult();
    final won = Completer<String?>();
    final notHome = <String>[];
    var started = 0;
    var finished = 0;
    var restStarted = false;
    Timer? staggerTimer;

    void settle(String? address) {
      if (!won.isCompleted) won.complete(address);
    }

    // Declared ahead: an attempt that fails early starts the rest, and
    // starting the rest makes attempts.
    late final void Function() startRest;

    void attempt(String candidate) {
      started++;
      unawaited(
        _try(candidate, fingerprint).then((outcome) {
          finished++;
          switch (outcome) {
            case _Outcome.home:
              settle(candidate);
            case _Outcome.otherKey:
              notHome.add(candidate);
            case _Outcome.unreachable:
              break;
          }
          if (restStarted && finished == started) settle(null);
          // The first candidate failed before its head start ran out: no
          // reason to keep the others waiting.
          if (!restStarted) startRest();
        }),
      );
    }

    startRest = () {
      if (restStarted || won.isCompleted) return;
      restStarted = true;
      staggerTimer?.cancel();
      candidates.skip(1).forEach(attempt);
      if (finished == started) settle(null);
    };

    attempt(candidates.first);
    staggerTimer = Timer(stagger, startRest);
    final budgetTimer = Timer(budget, () => settle(null));
    final address = await won.future;
    staggerTimer.cancel();
    budgetTimer.cancel();
    return DirectProbeResult(address: address, notHome: List<String>.unmodifiable(notHome));
  }

  Future<_Outcome> _try(String candidate, String fingerprint) async {
    final uri = Uri.tryParse('https://$candidate');
    if (uri == null || uri.host.isEmpty || !uri.hasPort) return _Outcome.unreachable;
    final deadline = Stopwatch()..start();
    ConnectionTask<SecureSocket>? task;
    SecureSocket? socket;
    var abandoned = false;
    try {
      task = await SecureSocket.startConnect(
        uri.host,
        uri.port,
        context: SecurityContext(withTrustedRoots: false),
        onBadCertificate: (_) => true,
        supportedProtocols: const <String>['http/1.1'],
      );
      final pending = task;
      socket = await pending.socket.timeout(
        attemptTimeout,
        onTimeout: () {
          abandoned = true;
          pending.cancel();
          // A handshake that finishes after all is closed on arrival.
          unawaited(pending.socket.then((late) => late.destroy(), onError: (Object _) {}));
          throw TimeoutException('direct probe');
        },
      );
      if (abandoned) return _Outcome.unreachable;
      if (!ServerPin.matches(socket.peerCertificate?.der, fingerprint)) return _Outcome.otherKey;
      socket.write('GET /health HTTP/1.1\r\nHost: ${uri.authority}\r\nConnection: close\r\n\r\n');
      await socket.flush();
      final left = attemptTimeout - deadline.elapsed;
      if (left <= Duration.zero) return _Outcome.unreachable;
      final status = await utf8.decoder.bind(socket).transform(const LineSplitter()).first.timeout(left);
      return status.startsWith('HTTP/1.1 200') || status.startsWith('HTTP/1.0 200') ? _Outcome.home : _Outcome.unreachable;
    } on Object {
      return _Outcome.unreachable;
    } finally {
      socket?.destroy();
    }
  }
}

enum _Outcome { home, otherKey, unreachable }
