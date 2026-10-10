@Tags(['live'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/chat/message_dao.dart';
import 'package:nox_app/data/remote/api_client.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/sync/connection/connection_path_selector.dart';
import 'package:nox_app/data/sync/connection/direct_prober.dart';
import 'package:nox_app/data/sync/outbox_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/connection/connection_path.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/domain/repository/connection/server_addresses_repository.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';
import 'package:nox_app/domain/service/attachment_download_service.dart';
import 'package:nox_app/domain/service/attachment_transfer_service.dart';
import 'package:nox_app/domain/service/network_change_service.dart';
import 'package:nox_tor/channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'live_harness.dart';
import 'live_target.dart';

/// Phase 043 end to end on this machine, through the real Tor network: a big
/// file up and down the onion service, with the link broken under it, the
/// queue "restarted" in the middle, and the path changed from Tor to direct
/// while the bytes are going - the app's own code throughout, against a `noxd`
/// whose onion service a separate tor publishes (phase 045).
///
/// What it proves: the file arrives whole both ways (SC-001), nothing that
/// already arrived is sent again (SC-002), neither a restart nor a change of
/// path starts a transfer over (SC-003), and no limit on the whole transfer
/// cuts it, however long it runs (SC-004).
///
/// Run by hand - it needs a tor binary and the Tor network, and 100 MiB take a
/// while:
///   (cd client_backend && go build -o /tmp/noxd .)
///   fvm flutter test test/live/resumable_files_probe.dart \
///     --dart-define=noxd=/tmp/noxd --dart-define=tor=/path/to/tor \
///     --dart-define=host=192.168.1.20 --dart-define=work=/tmp/nox_files_e2e [--dart-define=mib=100] [--dart-define=port=18543]
///
/// The work directory is emptied at the start; keep anything worth keeping
/// elsewhere. The server starts locked, and the harness unlocks it with its
/// probe password (phase 047).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const noxd = String.fromEnvironment('noxd');
  const tor = String.fromEnvironment('tor');
  const host = String.fromEnvironment('host');
  const work = String.fromEnvironment('work');
  const mib = int.fromEnvironment('mib', defaultValue: 100);
  const port = int.fromEnvironment('port', defaultValue: 18543);

  test(
    'a big file up and down through the onion service: broken, restarted and moved, and never sent twice',
    () async {
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

      // --- The file: deterministic bytes nothing could mistake for others. ---
      final size = mib * 1024 * 1024;
      final source = File('$work/big.bin');
      final random = Random(43);
      final out = source.openSync(mode: FileMode.write);
      for (var written = 0; written < size; written += 1024 * 1024) {
        out.writeFromSync(Uint8List.fromList(List<int>.generate(min(1024 * 1024, size - written), (_) => random.nextInt(256))));
      }
      out.closeSync();

      // --- tor as its own service, and the server on this machine's LAN
      // address, told where its onion service is (phase 045). ---
      final onionService = await LiveTor.start(tor: tor, work: work, target: '$host:$port');
      addTearDown(() => Process.killPid(onionService.pid));
      final server = await LiveNoxd.start(noxd: noxd, work: work, addr: '$host:$port', log: 'noxd.log', onionAddr: onionService.onion);
      addTearDown(() => Process.killPid(server.pid));
      final machine = await server.machineLink();

      // --- The app, with the two seams of the Tor probe. ---
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      await configureDependencies(Environment.dev);
      await getIt.allReady();
      getIt.allowReassignment = true;
      final away = AwayProber(ChannelDirectProber(const NativeNoxChannelApi()));
      final network = FakeNetwork();
      getIt.registerSingleton<DirectProber>(away);
      getIt.registerSingleton<NetworkChangeService>(network);
      final socket = getIt<NoxSocketClient>();
      final selector = getIt<ConnectionPathSelector>();
      bool liveOn(ConnectionPath path) => socket.currentPhase == SessionPhase.live && selector.currentPath == path;

      final auth = getIt<AuthRepository>();
      expect((await auth.signIn(identifier: machine)).hasData, isTrue, reason: 'sign-in by the machine link');
      expect((await auth.completeOnboarding(label: 'FilesProbe')).hasData, isTrue);
      await liveUntil('direct and live', const Duration(seconds: 30), () => liveOn(ConnectionPath.direct));
      // Tor only by the person's leave (phase 045).
      expect((await getIt<ServerAddressesRepository>().setUseTor(true)).hasData, isTrue);
      await liveUntil('the onion address', const Duration(minutes: 5), () async {
        return (await getIt<ServerAddressesRepository>().read()).data?.onion != null;
      });
      final chat = await getIt<ChatRepository>().createChat(name: 'Files probe ${DateTime.now().millisecondsSinceEpoch}');
      expect(chat.hasData, isTrue);
      final chatId = chat.data!.id;
      final outbox = getIt<OutboxService>()..start();

      // --- Away: the upload goes through Tor. ---
      away.away = true;
      network.change();
      await liveUntil('live through Tor', const Duration(minutes: 6), () => liveOn(ConnectionPath.tor));
      expect(getIt<ApiClient>().dio.options.baseUrl, contains('.onion'));

      final entry = (await getIt<OutboxRepository>().enqueue(
        chatId: chatId,
        attachment: MessageAttachment(
          id: 'att_local',
          type: FileType.other,
          name: 'big.bin',
          sizeBytes: size,
          mime: 'application/octet-stream',
          localPath: source.path,
        ),
      )).data!;
      final transfers = getIt<AttachmentTransferService>();
      double upShare() => transfers.current[entry.clientMessageId]?.fraction ?? 0;
      final upWatch = Stopwatch()..start();
      // Not awaited: a pass lasts as long as the whole upload does.
      unawaited(outbox.flush());

      // A broken link at a fifth of the way.
      await liveUntil('a fifth up', const Duration(minutes: 60), () => upShare() >= 0.2);
      measure('upload, first fifth through Tor: ${upWatch.elapsed.inSeconds} s');
      getIt<ApiClient>().cancelTransfers();

      // A "restart" of the queue at two fifths: the transfer ends, the drain
      // stops, and a fresh start finds the unfinished upload in its store.
      await liveUntil('two fifths up', const Duration(minutes: 60), () => upShare() >= 0.4);
      getIt<ApiClient>().cancelTransfers();
      await outbox.stop();
      outbox.start();
      unawaited(outbox.flush());
      await liveUntil('the upload going again', const Duration(minutes: 5), () => upShare() > 0);
      final restartedAt = upShare();
      measure('upload, after the restart the ring stood at ${(restartedAt * 100).floor()}%');
      expect(restartedAt, greaterThan(0.3), reason: 'it went on from what the server had, not from the first byte');

      // Home at seven tenths: the path changes under the transfer.
      await liveUntil('seven tenths up', const Duration(minutes: 60), () => upShare() >= 0.7);
      final atSwitch = upShare();
      away.away = false;
      network.change();
      await liveUntil('live direct', const Duration(seconds: 60), () => liveOn(ConnectionPath.direct));
      measure('upload, path changed to direct at ${(atSwitch * 100).floor()}%');

      await liveUntil('the message sent', const Duration(minutes: 90), () async => (await getIt<OutboxRepository>().pending()).isEmpty);
      measure('upload of $mib MiB, broken, restarted and moved: ${upWatch.elapsed.inSeconds} s');

      // What the server received, from its own log: each attempt resumed where
      // the last one's bytes stopped, or a little before (SC-002).
      final log = server.lines().toList();
      final froms = [
        for (final line in log)
          if (line['msg'] == 'upload resumed') (line['from'] as num).toInt(),
      ];
      final ats = [
        for (final line in log)
          if (line['msg'] == 'upload interrupted' || line['msg'] == 'upload stalled') (line['at'] as num).toInt(),
      ];
      // In the order the server saw them: what a break left, against where the
      // next attempt began. An attempt whose PUT never reached the server - a
      // connect through Tor that timed out - resumes twice from one break, and
      // pairing the two lists by position would charge it the next break.
      var again = 0;
      int? brokenAt;
      for (final line in log) {
        if (line['msg'] == 'upload interrupted' || line['msg'] == 'upload stalled') brokenAt = (line['at'] as num).toInt();
        if (line['msg'] == 'upload resumed' && brokenAt != null) {
          final from = (line['from'] as num).toInt();
          if (from < brokenAt) again += brokenAt - from;
          brokenAt = null;
        }
      }
      measure('upload attempts resumed from: $froms; broken at: $ats; bytes sent again: $again');
      expect(froms.where((f) => f > 0), isNotEmpty, reason: 'a resumed attempt started past the first byte');
      expect(again, lessThan(size ~/ 10), reason: 'only what was in flight is sent twice (SC-002)');
      expect(log.any((l) => l['msg'] == 'upload complete'), isTrue);

      // --- Down again, through Tor, with a break. ---
      final sent = (await getIt<MessageDao>().getByChatSorted(chatId)).lastWhere((m) => m.attachmentId != null);
      // The queue's own copy became this device's copy of the file, where a
      // download of it would land - so the download half asks for the bytes
      // as another device would, with that copy out of the way.
      final kept = await getIt<FileRepository>().localPathFor(fileId: sent.attachmentId!, suggestedName: 'big.bin');
      expect(kept, isNotNull, reason: 'the bytes this device sent stay on it');
      // Sealed, like everything the app keeps (phase 048): its plain length is
      // the file's.
      expect((await openSealed(kept!)).length, size);
      File(kept).deleteSync();
      final attachment = MessageAttachment(
        id: sent.attachmentId!,
        type: FileType.other,
        name: 'big.bin',
        sizeBytes: size,
        mime: 'application/octet-stream',
      );
      away.away = true;
      network.change();
      await liveUntil('live through Tor again', const Duration(minutes: 6), () => liveOn(ConnectionPath.tor));

      var downShare = 0.0;
      // The lowest share heard after the break: a download that started over
      // would report one near zero as its next attempt began.
      double? lowestAfterBreak;
      final downWatch = Stopwatch()..start();
      final fetching = getIt<AttachmentDownloadService>().fetch(
        attachment: attachment,
        onProgress: (share) {
          downShare = share;
          final lowest = lowestAfterBreak;
          if (lowest != null && share < lowest) lowestAfterBreak = share;
        },
      );
      await liveUntil('a third down', const Duration(minutes: 60), () => downShare >= 0.33);
      final downBrokenAt = downShare;
      lowestAfterBreak = downBrokenAt;
      getIt<ApiClient>().cancelTransfers();
      final fetched = await fetching.timeout(const Duration(minutes: 90));
      measure('download of $mib MiB through Tor, broken once: ${downWatch.elapsed.inSeconds} s');
      measure('download, broken at ${(downBrokenAt * 100).floor()}%, went on from ${(lowestAfterBreak! * 100).floor()}%');
      expect(fetched.hasData, isTrue, reason: 'download: ${fetched.exception}');
      expect(lowestAfterBreak, greaterThan(0.3), reason: 'it went on from the bytes already here, not from the first byte');

      // The same bytes, opened the way the app opens them and compared a
      // mebibyte at a time.
      await expectSamePlainBytes(fetched.data!, source);

      File('$work/measure.txt').writeAsStringSync('${measures.join('\n')}\n');
    },
    timeout: const Timeout(Duration(minutes: 240)),
  );
}
