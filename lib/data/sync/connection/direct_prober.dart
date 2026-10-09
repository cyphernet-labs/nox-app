import 'dart:async';
import 'dart:typed_data';

import 'package:injectable/injectable.dart';
import 'package:nox_tor/channel.dart';

/// What one round of direct attempts found (phase 040).
class DirectProbeResult {
  const DirectProbeResult({this.address, this.notHome = const <String>[]});

  /// The first candidate where this person's server proved its key; null when
  /// none did within the budget.
  final String? address;

  /// Candidates where a machine proved ANOTHER key. They do not lead home right
  /// now - an address is a place, and on another network the same one is
  /// somebody else's machine. Never a reason to call the server foreign, and
  /// never shown to anybody.
  final List<String> notHome;
}

/// Tries the server's direct addresses (phase 040).
abstract class DirectProber {
  /// Tries [candidates] in order of preference and returns the first where the
  /// server proves [serverKey] to a device proving the key of [deviceSeed].
  Future<DirectProbeResult> probe(List<String> candidates, {required Uint8List serverKey, required Uint8List deviceSeed});
}

/// Probes by opening a channel and closing it at once (phase 044).
///
/// Nothing short of the channel's own check says whose machine answered: the
/// TLS certificate is technical, and `/health` is not served on the main port
/// any more. An open that succeeds is "mine"; one refused as `wrongServer` is
/// "not mine" - silently passed over; anything else is "no answer". A probe
/// only says which address to dial: the socket's own connection is checked
/// again on its own channel.
@LazySingleton(as: DirectProber, env: [Environment.dev])
class ChannelDirectProber implements DirectProber {
  ChannelDirectProber(this._api);

  final NoxChannelApi _api;

  /// One address may take this long, transport, TLS and the check together.
  static const Duration attemptTimeout = Duration(milliseconds: 2500);

  /// The first candidate goes alone for this long - the one that answered last
  /// time usually answers again - and then the rest go together.
  static const Duration stagger = Duration(milliseconds: 300);

  /// The whole round. Tor starts no later than this after the attempt does
  /// (FR-002).
  static const Duration budget = Duration(seconds: 5);

  @override
  Future<DirectProbeResult> probe(List<String> candidates, {required Uint8List serverKey, required Uint8List deviceSeed}) async {
    if (candidates.isEmpty) return const DirectProbeResult();
    final won = Completer<String?>();
    // Opens still under way when the round is settled are dropped in the
    // module, not left to run out their time.
    final roundOver = Completer<void>();
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
        _try(candidate, serverKey: serverKey, deviceSeed: deviceSeed, cancel: roundOver.future).then((outcome) {
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
    roundOver.complete();
    return DirectProbeResult(address: address, notHome: List<String>.unmodifiable(notHome));
  }

  Future<_Outcome> _try(
    String candidate, {
    required Uint8List serverKey,
    required Uint8List deviceSeed,
    required Future<void> cancel,
  }) async {
    final uri = Uri.tryParse('https://$candidate');
    // An onion address is never a direct one: it goes through Tor or nowhere.
    if (uri == null || uri.host.isEmpty || !uri.hasPort || uri.host.toLowerCase().endsWith('.onion')) return _Outcome.unreachable;
    try {
      final channel = await _api.open(
        DirectTarget(uri.host, uri.port),
        deviceSeed: deviceSeed,
        serverKey: serverKey,
        timeout: attemptTimeout,
        cancel: cancel,
      );
      // Proved: that is all a probe wanted. Nothing is sent on it.
      channel.close();
      return _Outcome.home;
    } on ChannelOpenException catch (e) {
      return e.failure == ChannelFailure.wrongServer ? _Outcome.otherKey : _Outcome.unreachable;
    } on Object {
      return _Outcome.unreachable;
    }
  }
}

enum _Outcome { home, otherKey, unreachable }
