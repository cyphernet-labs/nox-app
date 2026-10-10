@Tags(['live'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/chat/message_dao.dart';
import 'package:nox_app/data/remote/api_client.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/repository/connection/connection_storage.dart';
import 'package:nox_app/data/sync/connection/connection_path_selector.dart';
import 'package:nox_app/data/sync/connection/direct_prober.dart';
import 'package:nox_app/data/sync/outbox_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/connection/connection_path.dart';
import 'package:nox_app/domain/service/connection_status_service.dart';
import 'package:nox_app/domain/model/connection/connection_settings.dart';
import 'package:nox_app/domain/model/connection/connection_problem.dart';
import 'package:nox_app/domain/model/connection/tor_status.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/domain/repository/connection/server_addresses_repository.dart';
import 'package:nox_app/domain/repository/device/device_repository.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:nox_app/domain/service/network_change_service.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';
import 'package:nox_app/domain/service/tor_service.dart';
import 'package:nox_app/general/pairing/pairing_link.dart';
import 'package:nox_tor/channel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'live_harness.dart';
import 'live_target.dart';

/// Phases 040 and 045 end to end on this machine, through the real Tor
/// network: the app's own code - path selector, Arti behind `package:nox_tor`,
/// every connection a channel of the module (phase 044) - against a `noxd`
/// whose onion service a SEPARATE tor publishes (phase 045): the probe starts
/// tor itself with an onion service on port 443 pointed at the server's port,
/// proof of work on, and hands the server the address with `-onion-addr`. No
/// access key opens the service; the app goes through Tor only once the
/// person has turned `Use Tor` on.
///
/// "Away from home" is the one thing simulated: a prober that finds no direct
/// address while [AwayProber.away] is set. Everything past it is real.
///
/// Run manually, not in the gate - it needs a tor binary and the Tor network,
/// and takes ten to twenty minutes:
///   (cd client_backend && go build -o /tmp/noxd .)
///   fvm flutter test test/live/tor_live_probe.dart \
///     --dart-define=noxd=/tmp/noxd --dart-define=tor=/path/to/tor \
///     --dart-define=host=192.168.1.20 --dart-define=work=/tmp/nox_e2e   # host: this machine's LAN address
///     [--dart-define=port=18443]          # the server's port; the moved server takes the next one
///     [--dart-define=other_onion=<56>.onion]   # another server's onion service, for «a different server»
///
/// The work directory is emptied at the start; keep anything worth keeping
/// elsewhere. Every start of the server - the first and the two over the same
/// database - is unlocked by the harness with its probe password (phase 047).
///
/// The LAN address matters: a server bound to loopback lists no direct address
/// at all (contract §3), and scenario 8 is about learning a new one. `noxd` and
/// tor are left running at the end, unlocked, with the service page's address
/// in `<work>/page.txt`, for `tor_pairing_probe.dart` and the simulator and
/// emulator runs of `integration_test/tor_pairing_test.dart` - which pair
/// through Tor from "away" by an invite their own issuing device allows
/// (phases 045 and 046). Each takes a fresh machine link:
///   /tmp/noxd link -status-addr "$(cat /tmp/nox_e2e/page.txt)"
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const noxd = String.fromEnvironment('noxd');
  const tor = String.fromEnvironment('tor');
  const host = String.fromEnvironment('host');
  const work = String.fromEnvironment('work');
  const port = int.fromEnvironment('port', defaultValue: 18443);
  const otherOnion = String.fromEnvironment('other_onion');

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

    // What did not go as the spec says, kept to the end so the run still
    // leaves its measures and the stand behind.
    final findings = <String>[];
    void finding(String line) {
      findings.add(line);
      stdout.writeln('FINDING: $line');
    }

    // --- tor as its own service, then the server on this machine's LAN
    // address, told where its onion service is. ---
    final firstTor = await LiveTor.start(tor: tor, work: work, target: '$host:$port');
    final first = await LiveNoxd.start(noxd: noxd, work: work, addr: '$host:$port', log: 'noxd1.log', onionAddr: firstTor.onion);
    final machine = await first.machineLink();
    stdout.writeln('NOXD: pid=${first.pid}; TOR: pid=${firstTor.pid}');
    expect(PairingLink.parse(machine).onionServiceKey, isNotNull, reason: 'the link carries the onion address the server was given');

    // --- The app, with two seams: where "away" comes from, and when the
    // network changes. Registered before anything resolves the selector.
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.dev);
    await getIt.allReady();
    getIt.allowReassignment = true;
    final away = AwayProber(ChannelDirectProber(const NativeNoxChannelApi()));
    final network = FakeNetwork();
    getIt.registerSingleton<DirectProber>(away);
    getIt.registerSingleton<NetworkChangeService>(network);

    final auth = getIt<AuthRepository>();
    final socket = getIt<NoxSocketClient>();
    final selector = getIt<ConnectionPathSelector>();
    final torService = getIt<TorService>();
    final addresses = getIt<ServerAddressesRepository>();

    bool liveOn(ConnectionPath path) => socket.currentPhase == SessionPhase.live && selector.currentPath == path;
    ConnectionProblem? problem() => getIt<ConnectionStatusService>().status.problem;

    /// Waits for one of [wanted] as the shown cause, and says which came and
    /// which others were seen on the way when none did.
    Future<ConnectionProblem?> cause(String what, Duration budget, Set<ConnectionProblem> wanted) async {
      final seen = <ConnectionProblem?>{};
      final clock = Stopwatch()..start();
      while (clock.elapsed < budget) {
        final now = problem();
        seen.add(now);
        if (wanted.contains(now)) return now;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      finding('$what: none of ${wanted.map((p) => p.name)} within ${budget.inSeconds} s; seen ${seen.map((p) => p?.name)}');
      return null;
    }

    // --- 1. Pair at home by the machine link, as the connection screen hands
    // it over: the link's addresses, Use Tor off. Direct; Tor never started.
    var watch = Stopwatch()..start();
    final link = PairingLink.parse(machine);
    final linkOnion = '${torService.onionFromPublicKey(link.onionServiceKey!)}:443';
    final signedIn = await auth.signIn(
      identifier: machine,
      connection: ConnectionSettings(serverAddress: link.directAddresses.first, onionAddress: linkOnion),
    );
    expect(signedIn.hasData, isTrue, reason: 'sign-in by the machine link');
    expect((await auth.completeOnboarding(label: 'TorProbe')).hasData, isTrue);
    await liveUntil('direct and live', const Duration(seconds: 30), () => liveOn(ConnectionPath.direct));
    measure('pairing at home, to live: ${watch.elapsedMilliseconds} ms');
    expect(torService.status.state, TorState.stopped, reason: 'Tor does not run on the direct path (FR-006)');
    await liveUntil('the server states its onion address', const Duration(seconds: 30), () async {
      return (await addresses.read()).data?.onion == '${firstTor.onion}:443';
    });

    // --- 1a. Away with Use Tor off: no way through Tor at all (SC-006). ---
    away.away = true;
    network.change();
    await liveUntil('no connection, and the cause', const Duration(seconds: 60), () {
      return getIt<ConnectionStatusService>().status.problem == ConnectionProblem.turnOnTor;
    });
    expect(torService.status.state, TorState.stopped, reason: 'with Use Tor off nothing is opened through Tor');
    away.away = false;
    network.change();
    await liveUntil('home again', const Duration(seconds: 30), () => liveOn(ConnectionPath.direct));

    // Tor only by the person's leave (phase 045).
    expect((await addresses.setUseTor(true)).hasData, isTrue);
    final chat = await getIt<ChatRepository>().createChat(name: 'Tor probe ${DateTime.now().millisecondsSinceEpoch}');
    expect(chat.hasData, isTrue, reason: 'a chat to talk in');
    final chatId = chat.data!.id;
    // A chat is made on the device first since phase 041; the outbox takes it
    // to the server, and only then can a message name it.
    getIt<OutboxService>().start();
    unawaited(getIt<OutboxService>().flush());
    await liveUntil('the chat on the server', const Duration(seconds: 30), () => getIt<ChatRepository>().isOnServer(chatId: chatId));
    Future<bool> send(String text) async {
      final sent = await getIt<MessageRepository>().sendMessage(chatId: chatId, clientMessageId: const Uuid().v4(), text: text);
      return sent.hasData;
    }

    expect(await send('direct 1'), isTrue);

    // Messages queued while the path changes under them: a send whose reply
    // went down with the old connection goes again on the new one, under the
    // same client_message_id, and the server keeps one (FR-012).
    final queued = <String>[];
    Future<void> enqueue(String text) async {
      final entry = await getIt<OutboxRepository>().enqueue(chatId: chatId, text: text);
      expect(entry.hasData, isTrue, reason: 'enqueue "$text"');
      queued.add(text);
      unawaited(getIt<OutboxService>().flush());
    }

    Future<void> burstAcross(String label, void Function() change) async {
      for (var i = 0; i < 3; i++) {
        await enqueue('$label, before $i');
      }
      change();
      for (var i = 0; i < 3; i++) {
        await enqueue('$label, during $i');
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }

    Future<void> expectEachOnce(String label) async {
      final texts = queued.where((t) => t.startsWith(label)).toList();
      await liveUntil('the queue drained ($label)', const Duration(minutes: 4), () async {
        return (await getIt<OutboxRepository>().pending()).isEmpty;
      });
      await liveUntil('the burst back from the server ($label)', const Duration(minutes: 2), () async {
        final rows = await getIt<MessageDao>().getByChatSorted(chatId);
        return texts.every((t) => rows.any((r) => r.text == t));
      });
      // A message the server stored twice comes back as a second row of its
      // own, a little later than the first.
      await Future<void>.delayed(const Duration(seconds: 3));
      final rows = await getIt<MessageDao>().getByChatSorted(chatId);
      final copies = {for (final t in texts) t: rows.where((r) => r.text == t).length};
      final wrong = copies.entries.where((e) => e.value != 1).toList();
      measure('$label: ${texts.length} messages queued across the switch, each stored ${wrong.isEmpty ? 'once' : 'NOT once: $wrong'}');
      if (wrong.isNotEmpty) finding('$label: not exactly once: $wrong');
    }

    // --- 2. Away: Tor comes up (cold) and the conversation goes on (US1). ---
    away.away = true;
    watch = Stopwatch()..start();
    network.change();
    await liveUntil('live through Tor', const Duration(minutes: 6), () => liveOn(ConnectionPath.tor));
    measure(
      'away, cold Tor, to live: ${watch.elapsedMilliseconds} ms (socket ${socket.currentUrl?.host.endsWith('.onion') ?? false ? 'onion' : 'direct'})',
    );
    measure('RSS on Tor: ${(ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(1)} MB');
    watch = Stopwatch()..start();
    expect(await send('through Tor 1'), isTrue, reason: 'a message through Tor');
    measure('a message through Tor, round trip: ${watch.elapsedMilliseconds} ms');

    // A file through Tor as well (US1/AC2, FR-009): the bytes travel over HTTPS
    // on a channel of their own, through Tor and checked as the commands' -
    // and come back the same.
    expect(getIt<ApiClient>().dio.options.baseUrl, contains('.onion'), reason: 'the bytes go the way the socket went');
    watch = Stopwatch()..start();
    final payload = List<int>.generate(64 * 1024, (i) => (i * 31 + 7) & 0xff);
    final source = File('$work/through_tor.bin')..writeAsBytesSync(payload);
    final uploaded = await getIt<FileRepository>().upload(path: source.path, mime: 'application/octet-stream');
    expect(uploaded.hasData, isTrue, reason: 'upload through Tor: ${uploaded.exception}');
    final fileId = uploaded.data!;
    final withFile = await getIt<MessageRepository>().sendMessage(
      chatId: chatId,
      clientMessageId: const Uuid().v4(),
      attachment: MessageAttachment(id: fileId, type: FileType.other, name: 'through_tor.bin', sizeBytes: payload.length),
    );
    expect(withFile.hasData, isTrue, reason: 'a message naming the file');
    final fetched = await getIt<FileRepository>().download(fileId: fileId, suggestedName: 'through_tor.bin');
    expect(fetched.hasData, isTrue, reason: 'download through Tor: ${fetched.exception}');
    // The bytes land sealed (phase 048): the plain ones come out of the file
    // the way the app reads it, never off the disk.
    expect(await (await openSealed(fetched.data!)).readAll(), payload, reason: 'the same bytes back');
    measure('a 64 KiB file through Tor, up, sent and down: ${watch.elapsedMilliseconds} ms');

    // --- 3. Home: back to direct, Tor stopped within ten seconds (SC-002),
    // with messages queued across the switch. ---
    away.away = false;
    await burstAcross('tor to direct', () {
      watch = Stopwatch()..start();
      network.change();
    });
    await liveUntil('live direct again', const Duration(seconds: 30), () => liveOn(ConnectionPath.direct));
    final toDirect = watch.elapsedMilliseconds;
    await liveUntil('Tor stopped', const Duration(seconds: 10), () => torService.status.state == TorState.stopped);
    measure('home, back to direct: $toDirect ms; Tor stopped after ${watch.elapsedMilliseconds} ms');
    await expectEachOnce('tor to direct');
    expect(await send('direct 2'), isTrue);

    // --- 2 again, warm, with messages queued across the switch. ---
    away.away = true;
    await burstAcross('direct to tor', () {
      watch = Stopwatch()..start();
      network.change();
    });
    await liveUntil('live through Tor, warm', const Duration(minutes: 4), () => liveOn(ConnectionPath.tor));
    measure('away, warm Tor, to live: ${watch.elapsedMilliseconds} ms');
    await expectEachOnce('direct to tor');
    expect(await send('through Tor 2'), isTrue);
    away.away = false;
    network.change();
    await liveUntil('home again', const Duration(seconds: 30), () => liveOn(ConnectionPath.direct));

    // --- 8. The server moves to another port: Tor brings the news, and the
    // app returns to the direct path on the new address. Nothing is wiped.
    // tor is pointed at the new port over the same keys, so the onion address
    // stays what the server already has in its database. ---
    final epoch = await getIt<SyncRepository>().getEpoch();
    final before = await _count(chatId);
    await first.stop();
    await firstTor.stop();
    final secondTor = await LiveTor.start(tor: tor, work: work, target: '$host:${port + 1}', log: 'tor2.log');
    expect(secondTor.onion, firstTor.onion, reason: 'the same keys, the same address');
    // The same database, so the same password opens it (phase 047).
    final second = await LiveNoxd.start(noxd: noxd, work: work, addr: '$host:${port + 1}', log: 'noxd2.log', password: first.password);
    stdout.writeln('NOXD: pid=${second.pid}; TOR: pid=${secondTor.pid}');
    watch = Stopwatch()..start();
    await liveUntil('live direct on the new address', const Duration(minutes: 8), () {
      return liveOn(ConnectionPath.direct) && socket.currentUrl?.port == port + 1;
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
    await liveUntil('live through Tor, cold, server long up', const Duration(minutes: 4), () => liveOn(ConnectionPath.tor));
    measure('away, cold Tor, server long up, to live: ${watch.elapsedMilliseconds} ms');
    watch = Stopwatch()..start();
    expect(await send('through Tor 3'), isTrue);
    measure('a message through Tor, round trip: ${watch.elapsedMilliseconds} ms');
    away.away = false;
    network.change();
    await liveUntil('home again', const Duration(seconds: 30), () => liveOn(ConnectionPath.direct));

    // --- 5. Why Tor does not get through, in the person's words (US5,
    // FR-017, the spec's edge cases). Away with Use Tor on: Tor is the only
    // way. An edit in Settings > Connection is applied the way the section
    // applies it - stored, then the channel started again. ---
    Future<void> reconnect() => getIt<SessionPhaseService>().reconnect();
    away.away = true;
    network.change();
    await liveUntil('live through Tor', const Duration(minutes: 4), () => liveOn(ConnectionPath.tor));

    // An onion address nobody publishes - a real key, so the address is
    // well formed down to its curve point.
    final nobodysKey = await (await Ed25519().newKeyPair()).extractPublicKey();
    final nobody = torService.onionFromPublicKey(Uint8List.fromList(nobodysKey.bytes))!;
    expect((await addresses.saveManual(manualAddress: null, manualOnion: '$nobody:443')).hasData, isTrue);
    watch = Stopwatch()..start();
    await reconnect();
    final unpublished = await cause('an onion address nobody publishes', const Duration(minutes: 5), {ConnectionProblem.onionNotFound});
    measure('an onion address nobody publishes: ${unpublished?.name ?? problem()?.name} after ${watch.elapsedMilliseconds} ms');

    // Another server's onion service: the channel check finds another key.
    if (otherOnion.isNotEmpty) {
      expect((await addresses.saveManual(manualAddress: null, manualOnion: '$otherOnion:443')).hasData, isTrue);
      watch = Stopwatch()..start();
      await reconnect();
      final other = await cause('another server\'s onion address', const Duration(minutes: 5), {ConnectionProblem.otherServer});
      measure('another server\'s onion address: ${other?.name ?? problem()?.name} after ${watch.elapsedMilliseconds} ms');
    }
    expect((await addresses.saveManual(manualAddress: null, manualOnion: null)).hasData, isTrue);
    await reconnect();
    await liveUntil('live through Tor, the server\'s own address back', const Duration(minutes: 4), () => liveOn(ConnectionPath.tor));

    // The server's tor stopped: the address is still in the directories, and
    // nothing answers behind it.
    watch = Stopwatch()..start();
    await secondTor.stop();
    final torGone = await cause('the server\'s tor stopped', const Duration(minutes: 6), {
      ConnectionProblem.onionNotFound,
      ConnectionProblem.onionUnreachable,
    });
    measure('the server\'s tor stopped: ${torGone?.name ?? problem()?.name} after ${watch.elapsedMilliseconds} ms');
    final thirdTor = await LiveTor.start(tor: tor, work: work, target: '$host:${port + 1}', log: 'tor3.log');
    expect(thirdTor.onion, firstTor.onion, reason: 'the same keys, the same address');
    watch = Stopwatch()..start();
    await liveUntil('live through Tor, the server\'s tor back', const Duration(minutes: 8), () => liveOn(ConnectionPath.tor));
    measure('the server\'s tor back, live through Tor again: ${watch.elapsedMilliseconds} ms');

    // The server stopped behind a running tor: the service answers, the
    // server behind it does not.
    watch = Stopwatch()..start();
    await second.stop();
    final serverGone = await cause('the server stopped behind a running tor', const Duration(minutes: 6), {
      ConnectionProblem.onionUnreachable,
    });
    measure('the server stopped behind a running tor: ${serverGone?.name ?? problem()?.name} after ${watch.elapsedMilliseconds} ms');
    final third = await LiveNoxd.start(noxd: noxd, work: work, addr: '$host:${port + 1}', log: 'noxd3.log', password: first.password);
    stdout.writeln('NOXD: pid=${third.pid}; TOR: pid=${thirdTor.pid}');
    watch = Stopwatch()..start();
    await liveUntil('live through Tor, the server back', const Duration(minutes: 6), () => liveOn(ConnectionPath.tor));
    measure('the server back, live through Tor again: ${watch.elapsedMilliseconds} ms');

    // Home with no network change to say so: the periodic look at the direct
    // path finds it within two minutes (SC-002).
    away.away = false;
    watch = Stopwatch()..start();
    await liveUntil('back to direct with no network change', const Duration(minutes: 3), () => liveOn(ConnectionPath.direct));
    measure('home with no network change, back to direct: ${watch.elapsedMilliseconds} ms');
    expect(await send('direct after the causes'), isTrue);

    // --- 4. Invites are version 3 and carry the onion address, so a new
    // device can pair through Tor from anywhere (phase 045). An invite pairs
    // nothing until the device that issued it says Allow (phase 046), and this
    // one is gone once the probe ends: the runs that pair through Tor next
    // bring an issuing device of their own, by a machine link. ---
    final invite = await getIt<DeviceRepository>().inviteDevice();
    expect(invite.hasData, isTrue);
    expect(invite.data!.onion, isTrue, reason: 'the card does not say home only');
    expect(invite.data!.homeOnly, isFalse);
    final parsed = PairingLink.parse(invite.data!.link);
    expect(parsed.directAddresses, isNotEmpty);
    expect(parsed.onionServiceKey, isNotNull);
    File('$work/page.txt').writeAsStringSync('${third.pageAddress}\n');

    // --- 7. Logout leaves no addresses and no Tor state (SC-007). A forced
    // one, the wipe a revocation brings: nothing is asked of the server. ---
    final support = await getApplicationSupportDirectory();
    expect((await auth.logout(forced: true)).hasData, isTrue);
    const storage = FlutterSecureStorage();
    expect(await storage.read(key: ConnectionStorage.serverAddresses), isNull);
    expect(Directory('${support.path}${Platform.pathSeparator}nox_tor_state').existsSync(), isFalse);

    File('$work/measure.txt').writeAsStringSync('${[...measures, ...findings.map((f) => 'FINDING: $f')].join('\n')}\n');
    stdout.writeln(
      'STAND: noxd left running, unlocked, pid ${third.pid}, its page at ${third.pageAddress} ($work/page.txt); tor, pid ${thirdTor.pid}',
    );
    expect(findings, isEmpty, reason: 'what did not go as the spec says');
  }, timeout: const Timeout(Duration(minutes: 50)));
}

Future<int> _count(String chatId) async => (await getIt<MessageDao>().getByChatSorted(chatId)).length;
