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

/// A `noxd` run detached from the probe, so it can outlive it.
class LiveNoxd {
  LiveNoxd._(this.pid, this._log);

  final int pid;
  final File _log;

  static Future<LiveNoxd> start({
    required String noxd,
    required String tor,
    required String work,
    required String addr,
    required String log,
  }) async {
    final file = File('$work/$log');
    final shell = await Process.run('/bin/sh', [
      '-c',
      '"$noxd" -addr $addr -db "$work/probe.db" -tor -tor-bin "$tor" -status-addr "" > "${file.path}" 2>&1 & echo \$!',
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
