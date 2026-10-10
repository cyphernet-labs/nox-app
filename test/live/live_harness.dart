import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/sync/connection/direct_prober.dart';
import 'package:nox_app/domain/service/network_change_service.dart';

/// What the live probes share: a `noxd` of their own, "away from home" on
/// demand, and a network that changes when told to. Not a test - imported by
/// the probes under `test/live/`, none of which the suite ever collects.

/// Waits for [done], failing the probe when [budget] runs out first.
Future<void> liveUntil(String what, Duration budget, FutureOr<bool> Function() done) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < budget) {
    if (await done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('not reached within ${budget.inSeconds} s: $what');
}

/// "Away from home": while [away] is set, no direct address answers.
class AwayProber implements DirectProber {
  AwayProber(this._real);

  final DirectProber _real;
  bool away = false;

  @override
  Future<DirectProbeResult> probe(List<String> candidates, {required Uint8List serverKey, required Uint8List deviceSeed}) => away
      ? Future<DirectProbeResult>.value(const DirectProbeResult())
      : _real.probe(candidates, serverKey: serverKey, deviceSeed: deviceSeed);
}

/// A network that changes when [change] says so.
class FakeNetwork implements NetworkChangeService {
  final StreamController<void> _changes = StreamController<void>.broadcast();

  void change() => _changes.add(null);

  @override
  Stream<void> watchChanges() => _changes.stream;
}

/// A tor of the probe's own, run as the separate service the server expects
/// since phase 045 - set up the way the install script sets it up: an onion
/// service on port 443 pointed at the server's port, proof-of-work defences
/// on, no SOCKS port. The server never starts it, never sees its keys, and
/// learns its address only through `-onion-addr`.
///
/// Its directories live under `<work>`: the service's keys in `<work>/hs`, so
/// a tor started again over the same work directory keeps the same onion
/// address - what a server moved to another port looks like from outside.
class LiveTor {
  LiveTor._(this.pid, this.onion);

  final int pid;

  /// `<56>.onion`, as tor wrote it to `<work>/hs/hostname`.
  final String onion;

  /// Starts tor with an onion service that forwards to [target], the address
  /// `noxd` listens on - `127.0.0.1:<port>` for a server listening on all
  /// interfaces, its LAN address for one bound to it, as the probes' are.
  static Future<LiveTor> start({required String tor, required String work, required String target, String log = 'tor.log'}) async {
    final torrc = File('$work/torrc')
      ..writeAsStringSync(
        [
          'SocksPort 0',
          'DataDirectory $work/tor-data',
          'HiddenServiceDir $work/hs',
          'HiddenServicePort 443 $target',
          'HiddenServicePoWDefensesEnabled 1',
          'Log notice file $work/$log',
        ].join('\n'),
      );
    final shell = await Process.run('/bin/sh', ['-c', '"$tor" -f "${torrc.path}" > /dev/null 2>&1 & echo \$!']);
    final pid = int.parse((shell.stdout as String).trim());
    final hostname = File('$work/hs/hostname');
    await liveUntil(
      'tor writes the onion address',
      const Duration(seconds: 60),
      () => hostname.existsSync() && hostname.readAsStringSync().trim().isNotEmpty,
    );
    return LiveTor._(pid, hostname.readAsStringSync().trim());
  }

  Future<void> stop() async {
    Process.killPid(pid);
    await Future<void>.delayed(const Duration(seconds: 1));
  }
}

/// A `noxd` run detached from the probe, so it can outlive it.
class LiveNoxd {
  LiveNoxd._(this.pid, this._log);

  final int pid;
  final File _log;

  /// Starts `noxd` on [addr]. [onionAddr] is the address of the onion
  /// service a separate tor publishes for it ([LiveTor]); the server only
  /// stores it and hands it out (phase 045).
  static Future<LiveNoxd> start({
    required String noxd,
    required String work,
    required String addr,
    required String log,
    String? onionAddr,
  }) async {
    final file = File('$work/$log');
    final onion = onionAddr == null ? '' : '-onion-addr $onionAddr';
    final shell = await Process.run('/bin/sh', [
      '-c',
      '"$noxd" -addr $addr -db "$work/probe.db" $onion -status-addr "" > "${file.path}" 2>&1 & echo \$!',
    ]);
    final pid = int.parse((shell.stdout as String).trim());
    final server = LiveNoxd._(pid, file);
    await liveUntil('noxd listening on $addr', const Duration(seconds: 30), () => server.lines().any((l) => l['msg'] == 'listening'));
    return server;
  }

  /// The server's log, one JSON object per line.
  Iterable<Map<String, dynamic>> lines() sync* {
    if (!_log.existsSync()) return;
    for (final line in _log.readAsLinesSync()) {
      try {
        final json = jsonDecode(line);
        if (json is Map<String, dynamic>) yield json;
      } on FormatException {
        continue;
      }
    }
  }

  Future<String> claimLink() async {
    String? link;
    await liveUntil('the claim link', const Duration(seconds: 10), () {
      link = lines().map((l) => l['link']).whereType<String>().firstOrNull;
      return link != null;
    });
    return link!;
  }

  Future<void> stop() async {
    Process.killPid(pid);
    await liveUntil('noxd stopped', const Duration(seconds: 30), () => lines().any((l) => l['msg'] == 'server stopped'));
  }
}
