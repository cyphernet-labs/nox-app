import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/local/device_vault.dart';
import 'package:nox_app/data/local/sealed_file.dart';
import 'package:nox_app/data/sync/connection/direct_prober.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/service/network_change_service.dart';

/// What the live probes share: a `noxd` of their own, "away from home" on
/// demand, a network that changes when told to, and the files the app keeps
/// read the way it reads them. Not a test - imported by the probes under
/// `test/live/`, none of which the suite ever collects.

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
/// on, at most 16 streams at once on a circuit, no SOCKS port. The server
/// never starts it, never sees its keys, and learns its address only through
/// `-onion-addr`.
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
  /// interfaces, its LAN address for one bound to it, as the probes' are. tor
  /// then connects from that same address, and the server counts it as this
  /// machine's, the way it counts loopback.
  static Future<LiveTor> start({required String tor, required String work, required String target, String log = 'tor.log'}) async {
    final torrc = File('$work/torrc')
      ..writeAsStringSync(
        [
          'SocksPort 0',
          'DataDirectory $work/tor-data',
          'HiddenServiceDir $work/hs',
          'HiddenServicePort 443 $target',
          'HiddenServicePoWDefensesEnabled 1',
          // Proof of work prices new circuits, not the streams on one already
          // built: at most 16 at once on a circuit, and one that asks for more
          // is closed whole.
          'HiddenServiceMaxStreams 16',
          'HiddenServiceMaxStreamsCloseCircuit 1',
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
///
/// It starts LOCKED (phase 047): its data is sealed under a password, only
/// the service page listens, and the main port opens once the password is
/// in. [start] enters it the way an install script does - `noxd unlock`, the
/// password piped on its standard input - and returns once the server
/// listens.
class LiveNoxd {
  LiveNoxd._(this.pid, this._log, this.pagePort, this.password);

  /// The password the probes' servers are given. A fresh database takes it
  /// as its first password; a server started again over the same work
  /// directory is opened with it again - one it was not given would not open
  /// the data.
  static const String probePassword = 'nox-live-probe-password';

  final int pid;
  final File _log;

  /// The loopback port of the server's service page - where the password
  /// goes in (phase 047), and where its machine link is while no device is
  /// paired: the server never writes one to its log (phases 045 and 046).
  final int pagePort;

  /// What this server's data opens with.
  final String password;

  /// The service page's address, as `noxd link` and `noxd unlock` take it in
  /// `-status-addr`.
  String get pageAddress => '127.0.0.1:$pagePort';

  /// Starts `noxd` on [addr], with its service page on a free loopback port,
  /// and unlocks it with [password]. [onionAddr] is the address of the onion
  /// service a separate tor publishes for it ([LiveTor]); the server only
  /// stores it and hands it out (phase 045).
  static Future<LiveNoxd> start({
    required String noxd,
    required String work,
    required String addr,
    required String log,
    String? onionAddr,
    String password = probePassword,
  }) async {
    final file = File('$work/$log');
    final onion = onionAddr == null ? '' : '-onion-addr $onionAddr';
    final page = await _freeLoopbackPort();
    final shell = await Process.run('/bin/sh', [
      '-c',
      '"$noxd" -addr $addr -db "$work/probe.db" $onion -status-addr 127.0.0.1:$page > "${file.path}" 2>&1 & echo \$!',
    ]);
    final pid = int.parse((shell.stdout as String).trim());
    final server = LiveNoxd._(pid, file, page, password);
    // The lock's line is written once the page listens: before it, a
    // `noxd unlock` would find nobody to give the password to.
    await liveUntil('noxd waiting for its password', const Duration(seconds: 30), () {
      server._failOnError();
      return server.lines().any(_isLockLine);
    });
    await server._unlock(noxd);
    await liveUntil('noxd listening on $addr', const Duration(seconds: 60), () {
      server._failOnError();
      return server.lines().any((l) => l['msg'] == 'listening');
    });
    return server;
  }

  /// The lines a server waiting for its password writes (phase 047): the
  /// first password of a fresh one, or the password of a locked one.
  static bool _isLockLine(Map<String, dynamic> line) {
    final msg = line['msg'];
    return msg is String && (msg.startsWith('no password is set yet') || msg.startsWith('this server is locked'));
  }

  /// A server that cannot start - its port taken, its database another
  /// build's - logs why and exits: said at once rather than waited out.
  void _failOnError() {
    for (final line in lines()) {
      if (line['level'] == 'ERROR') fail('noxd could not start: ${line['msg']}: ${line['err']}');
    }
  }

  /// `noxd unlock` with the password on its standard input, twice: a fresh
  /// server reads the password and its repeat, a locked one the first line
  /// alone.
  Future<void> _unlock(String noxd) async {
    final unlock = await Process.start(noxd, ['unlock', '-status-addr', pageAddress]);
    final out = unlock.stdout.transform(utf8.decoder).join();
    final err = unlock.stderr.transform(utf8.decoder).join();
    unlock.stdin.write('$password\n$password\n');
    try {
      await unlock.stdin.close();
    } on Object {
      // A command that ended before reading both lines says why in its exit
      // code and its output, below.
    }
    final code = await unlock.exitCode.timeout(const Duration(minutes: 2));
    if (code != 0) fail('noxd unlock exited with $code: ${(await err).trim()} ${(await out).trim()}');
  }

  static Future<int> _freeLoopbackPort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
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

  /// The machine link, as the service page shows it while no device is paired. Needs the network let
  /// through (`LiveTarget.letTheNetworkThrough`): the page is plain HTTP.
  Future<String> machineLink() async {
    String? link;
    await liveUntil('the machine link on the service page', const Duration(seconds: 10), () async {
      link = await _linkOnPage();
      return link != null;
    });
    return link!;
  }

  Future<String?> _linkOnPage() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final response = await (await client.getUrl(Uri.parse('http://$pageAddress/'))).close();
      final page = await response.transform(utf8.decoder).join();
      return RegExp(r'nox://pair/[A-Za-z0-9_-]+').firstMatch(page)?.group(0);
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> stop() async {
    Process.killPid(pid);
    await liveUntil('noxd stopped', const Duration(seconds: 30), () => lines().any((l) => l['msg'] == 'server stopped'));
  }
}

/// Opens a file the app keeps on the disk - a download, the queue's kept
/// copy - the way the app opens it (phase 048). It has to be sealed under this
/// device's local-data key: a plain file there is the very defect the phase
/// closed, and the plain bytes come out of the reader, not off the disk.
Future<SealedReader> openSealed(String path) async {
  final file = File(path);
  expect(await SealedFile.isSealed(file), isTrue, reason: 'what the app keeps on the disk is sealed (phase 048)');
  await getIt<DeviceVault>().ensureOpen();
  return (await SealedReader.open(file))!;
}

/// The plain bytes of the sealed file at [path] against [source], a mebibyte
/// at a time: neither side of a big file is ever in memory whole.
Future<void> expectSamePlainBytes(String path, File source) async {
  final plain = await openSealed(path);
  final size = source.lengthSync();
  expect(plain.length, size, reason: 'the plain length');
  const window = 1024 * 1024;
  final original = await source.open();
  final held = Uint8List(window);
  var filled = 0;
  var at = 0;
  Future<void> compare() async {
    final want = await original.read(filled);
    if (want.length != filled) fail('the source ends at ${at + want.length}, the file goes on');
    for (var i = 0; i < filled; i++) {
      if (want[i] != held[i]) fail('the bytes differ at ${at + i}');
    }
    at += filled;
    filled = 0;
  }

  try {
    await for (final chunk in plain.read()) {
      var taken = 0;
      while (taken < chunk.length) {
        final n = min(window - filled, chunk.length - taken);
        held.setRange(filled, filled + n, chunk, taken);
        filled += n;
        taken += n;
        if (filled == window) await compare();
      }
    }
    if (filled > 0) await compare();
  } finally {
    await original.close();
  }
  expect(at, size, reason: 'every byte compared');
}
