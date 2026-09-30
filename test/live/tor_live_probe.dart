@Tags(['live'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/chat/message_dao.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/repository/connection/connection_storage.dart';
import 'package:nox_app/data/sync/connection/connection_path_selector.dart';
import 'package:nox_app/data/sync/connection/direct_prober.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/connection/connection_path.dart';
import 'package:nox_app/domain/model/connection/tor_status.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/connection/access_key_repository.dart';
import 'package:nox_app/domain/repository/connection/server_addresses_repository.dart';
import 'package:nox_app/domain/repository/device/device_repository.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:nox_app/domain/service/network_change_service.dart';
import 'package:nox_app/domain/service/tor_service.dart';
import 'package:nox_app/general/pairing/pairing_link.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'live_target.dart';

/// Phase 040 end to end on this machine, through the real Tor network: the
/// app's own code - path selector, Arti behind `package:nox_tor`, the pinned
/// client over the bridge - against a `noxd` that publishes its onion service.
///
/// "Away from home" is the one thing simulated: a prober that finds no direct
/// address while [_AwayProber.away] is set. Everything past it is real.
///
/// Run manually, not in the gate - it needs a tor binary and the Tor network,
/// and takes minutes:
///   (cd client_backend && go build -o /tmp/noxd .)
///   fvm flutter test test/live/tor_live_probe.dart \
///     --dart-define=noxd=/tmp/noxd --dart-define=tor=/path/to/tor \
///     --dart-define=host=192.168.1.20 --dart-define=work=/tmp/nox_e2e   # host: this machine's LAN address
///
/// The LAN address matters: a server bound to loopback lists no direct address
/// at all (contract §3), and scenario 8 is about learning a new one. `noxd` is
/// left running at the end, with two version-2 invites in `<work>/invites.txt`,
/// for the simulator and emulator runs of `integration_test/tor_pairing_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const noxd = String.fromEnvironment('noxd');
  const tor = String.fromEnvironment('tor');
  const host = String.fromEnvironment('host');
  const work = String.fromEnvironment('work');

  test('away, home, a new address and back - through the real Tor network', () async {
    if (noxd.isEmpty || tor.isEmpty || host.isEmpty || work.isEmpty) {
      stdout.writeln('SKIP: pass --dart-define=noxd=, tor=, host= and work=');
      return;
    }
    LiveTarget.letTheNetworkThrough();
    final dir = Directory(work);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final measures = <String>[];
    void measure(String line) {
      measures.add(line);
      stdout.writeln('MEASURE: $line');
    }

    // --- The server, on this machine's LAN address, with tor. ---
    final first = await _Noxd.start(noxd: noxd, tor: tor, work: work, addr: '$host:18443', log: 'noxd1.log');
    final claim = await first.claimLink();
    stdout.writeln('NOXD: pid=${first.pid}');

    // --- The app, with two seams: where "away" comes from, and when the
    // network changes. Registered before anything resolves the selector.
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.dev);
    await getIt.allReady();
    getIt.allowReassignment = true;
    final away = _AwayProber(TlsDirectProber());
    final network = _Network();
    getIt.registerSingleton<DirectProber>(away);
    getIt.registerSingleton<NetworkChangeService>(network);

    final auth = getIt<AuthRepository>();
    final socket = getIt<NoxSocketClient>();
    final selector = getIt<ConnectionPathSelector>();
    final torService = getIt<TorService>();
    final addresses = getIt<ServerAddressesRepository>();

    bool liveOn(ConnectionPath path) => socket.currentPhase == SessionPhase.live && selector.currentPath == path;

    // --- 1. Pair at home by the claim link: direct, Tor never started. ---
    var watch = Stopwatch()..start();
    final signedIn = await auth.signIn(identifier: claim);
    expect(signedIn.hasData, isTrue, reason: 'sign-in by the claim link');
    expect((await auth.completeOnboarding(label: 'TorProbe')).hasData, isTrue);
    await _until('direct and live', const Duration(seconds: 30), () => liveOn(ConnectionPath.direct));
    measure('pairing at home, to live: ${watch.elapsedMilliseconds} ms');
    expect(torService.status.state, TorState.stopped, reason: 'Tor does not run on the direct path (FR-006)');
    await _until('the key registered', const Duration(seconds: 30), () async {
      return (await getIt<AccessKeyRepository>().isRegistered()).data ?? false;
    });
    await _until('the server offers its onion address', const Duration(minutes: 5), () async {
      return (await addresses.read()).data?.onion != null;
    });
    final chat = await getIt<ChatRepository>().createChat(name: 'Tor probe ${DateTime.now().millisecondsSinceEpoch}');
    expect(chat.hasData, isTrue, reason: 'a chat to talk in');
    final chatId = chat.data!.id;
    Future<bool> send(String text) async {
      final sent = await getIt<MessageRepository>().sendMessage(chatId: chatId, clientMessageId: const Uuid().v4(), text: text);
      return sent.hasData;
    }

    expect(await send('direct 1'), isTrue);

    // --- 2. Away: Tor comes up (cold) and the conversation goes on (US1). ---
    away.away = true;
    watch = Stopwatch()..start();
    network.change();
    await _until('live through Tor', const Duration(minutes: 6), () => liveOn(ConnectionPath.tor));
    measure(
      'away, cold Tor, to live: ${watch.elapsedMilliseconds} ms (socket ${socket.currentUrl?.host.endsWith('.onion') ?? false ? 'onion' : 'direct'})',
    );
    measure('RSS on Tor: ${(ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(1)} MB');
    watch = Stopwatch()..start();
    expect(await send('through Tor 1'), isTrue, reason: 'a message through Tor');
    measure('a message through Tor, round trip: ${watch.elapsedMilliseconds} ms');

    // --- 3. Home: back to direct, Tor stopped within ten seconds (SC-002). ---
    away.away = false;
    watch = Stopwatch()..start();
    network.change();
    await _until('live direct again', const Duration(seconds: 30), () => liveOn(ConnectionPath.direct));
    final toDirect = watch.elapsedMilliseconds;
    await _until('Tor stopped', const Duration(seconds: 10), () => torService.status.state == TorState.stopped);
    measure('home, back to direct: $toDirect ms; Tor stopped after ${watch.elapsedMilliseconds} ms');
    expect(await send('direct 2'), isTrue);

    // --- 2 again, warm. ---
    away.away = true;
    watch = Stopwatch()..start();
    network.change();
    await _until('live through Tor, warm', const Duration(minutes: 4), () => liveOn(ConnectionPath.tor));
    measure('away, warm Tor, to live: ${watch.elapsedMilliseconds} ms');
    expect(await send('through Tor 2'), isTrue);
    away.away = false;
    network.change();
    await _until('home again', const Duration(seconds: 30), () => liveOn(ConnectionPath.direct));

    // --- 8. The server moves to another port: Tor brings the news, and the
    // app returns to the direct path on the new address. Nothing is wiped. ---
    final epoch = await getIt<SyncRepository>().getEpoch();
    final before = await _count(chatId);
    await first.stop();
    final second = await _Noxd.start(noxd: noxd, tor: tor, work: work, addr: '$host:18444', log: 'noxd2.log');
    stdout.writeln('NOXD: pid=${second.pid}');
    watch = Stopwatch()..start();
    await _until('live direct on the new address', const Duration(minutes: 8), () {
      return liveOn(ConnectionPath.direct) && socket.currentUrl?.port == 18444;
    });
    measure('new server address, back to direct on it: ${watch.elapsedMilliseconds} ms');
    expect(await getIt<SyncRepository>().getEpoch(), epoch, reason: 'the world is named by the key, not the address');
    expect(await _count(chatId), before, reason: 'history is where it was (SC-003)');
    expect(await send('direct on the new address'), isTrue);

    // --- SC-001 under its own conditions: a server whose onion service has
    // been up for a while, and a Tor client starting cold (its directories
    // wiped). The cold run above met a descriptor published a minute earlier.
    await torService.wipe();
    away.away = true;
    watch = Stopwatch()..start();
    network.change();
    await _until('live through Tor, cold, server long up', const Duration(minutes: 4), () => liveOn(ConnectionPath.tor));
    measure('away, cold Tor, server long up, to live: ${watch.elapsedMilliseconds} ms');
    watch = Stopwatch()..start();
    expect(await send('through Tor 3'), isTrue);
    measure('a message through Tor, round trip: ${watch.elapsedMilliseconds} ms');
    away.away = false;
    network.change();
    await _until('home again', const Duration(seconds: 30), () => liveOn(ConnectionPath.direct));

    // --- 4. Invites from here work from anywhere: version 2, onion. ---
    final invites = <String>[];
    for (var i = 0; i < 2; i++) {
      final invite = await getIt<DeviceRepository>().inviteDevice();
      expect(invite.hasData, isTrue);
      expect(invite.data!.onion, isTrue, reason: 'the server could put its onion address in (FR-019)');
      expect(PairingLink.parse(invite.data!.link).carriesOnion, isTrue);
      invites.add(invite.data!.link);
    }
    File('$work/invites.txt').writeAsStringSync('${invites.join('\n')}\n');

    // --- 7. Logout leaves no key, no addresses, no Tor state (SC-007). A forced
    // one, which keeps the device on the server: the invites above are its. ---
    final support = await getApplicationSupportDirectory();
    expect((await auth.logout(forced: true)).hasData, isTrue);
    const storage = FlutterSecureStorage();
    expect(await storage.read(key: ConnectionStorage.accessKey), isNull);
    expect(await storage.read(key: ConnectionStorage.serverAddresses), isNull);
    expect(Directory('${support.path}${Platform.pathSeparator}nox_tor_state').existsSync(), isFalse);

    File('$work/measure.txt').writeAsStringSync('${measures.join('\n')}\n');
    stdout.writeln('INVITES: ${invites.length} written to $work/invites.txt; noxd left running, pid ${second.pid}');
  }, timeout: const Timeout(Duration(minutes: 30)));
}

Future<void> _until(String what, Duration budget, FutureOr<bool> Function() done) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < budget) {
    if (await done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('not reached within ${budget.inSeconds} s: $what');
}

Future<int> _count(String chatId) async => (await getIt<MessageDao>().getByChatSorted(chatId)).length;

class _AwayProber implements DirectProber {
  _AwayProber(this._real);

  final DirectProber _real;
  bool away = false;

  @override
  Future<DirectProbeResult> probe(List<String> candidates, {required String fingerprint}) =>
      away ? Future<DirectProbeResult>.value(const DirectProbeResult()) : _real.probe(candidates, fingerprint: fingerprint);
}

class _Network implements NetworkChangeService {
  final StreamController<void> _changes = StreamController<void>.broadcast();

  void change() => _changes.add(null);

  @override
  Stream<void> watchChanges() => _changes.stream;
}

/// A `noxd` run detached from the test, so it can outlive it.
class _Noxd {
  _Noxd._(this.pid, this._log);

  final int pid;
  final File _log;

  static Future<_Noxd> start({
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
    final server = _Noxd._(pid, file);
    await _until('noxd listening on $addr', const Duration(seconds: 30), () => server._lines().any((l) => l['msg'] == 'listening'));
    return server;
  }

  Iterable<Map<String, dynamic>> _lines() sync* {
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
    await _until('the claim link', const Duration(seconds: 10), () {
      link = _lines().map((l) => l['link']).whereType<String>().firstOrNull;
      return link != null;
    });
    return link!;
  }

  Future<void> stop() async {
    Process.killPid(pid);
    await _until('noxd stopped', const Duration(seconds: 30), () => _lines().any((l) => l['msg'] == 'server stopped'));
  }
}
