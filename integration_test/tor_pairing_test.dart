import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:integration_test/integration_test.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/sync/connection/connection_path_selector.dart';
import 'package:nox_app/data/sync/connection/direct_prober.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_app/domain/model/connection/connection_path.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/connection/server_addresses_repository.dart';
import 'package:nox_app/domain/repository/device/device_repository.dart';
import 'package:nox_app/domain/service/tor_service.dart';
import 'package:nox_app/general/pairing/pairing_link.dart';
import 'package:nox_tor/channel.dart';
import 'package:uuid/uuid.dart';

/// "Away from home" on demand: while [away] is set, no direct address answers.
class _AwayProber implements DirectProber {
  _AwayProber(this._real);

  final DirectProber _real;
  bool away = false;

  @override
  Future<DirectProbeResult> probe(List<String> candidates, {required Uint8List serverKey, required Uint8List deviceSeed}) => away
      ? Future<DirectProbeResult>.value(const DirectProbeResult())
      : _real.probe(candidates, serverKey: serverKey, deviceSeed: deviceSeed);
}

/// Device B of the phase 040 quickstart, scenario 5, on a simulator or an
/// emulator - as phase 044 leaves it: an invite pairs AT HOME, directly (the
/// onion service opens only for a paired device's key until phase 045), and
/// the device then goes away and talks to its server through Tor over its own
/// key. The Tor client and the channel are the real ones, in the app's
/// process on that platform.
///
/// Manual, like the live probes: it needs a running `noxd` with tor, reachable
/// at the invite's direct address from the device, and a fresh invite -
/// `test/live/tor_live_probe.dart` leaves both behind:
///   fvm flutter test integration_test/tor_pairing_test.dart -d DEVICE --dart-define=link=INVITE
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const link = String.fromEnvironment('link');

  testWidgets('an invite pairs at home, and the device then talks through Tor over its own key', (tester) async {
    if (link.isEmpty) {
      debugPrint('SKIP: pass --dart-define=link=<nox://pair/ invite>');
      return;
    }
    await configureDependencies(Environment.dev);
    await getIt.allReady();
    await getIt<AppConfigRepository>().initialize(flavorType: AppFlavorType.stage);
    // Registered before anything resolves the path selector.
    getIt.allowReassignment = true;
    final away = _AwayProber(ChannelDirectProber(const NativeNoxChannelApi()));
    getIt.registerSingleton<DirectProber>(away);
    final tor = getIt<TorService>();
    final invite = PairingLink.parse(link);
    final serviceKey = invite.onionServiceKey;
    final derived = serviceKey == null ? null : tor.onionFromPublicKey(serviceKey);
    debugPrint('TOR: supported=${tor.isSupported} status=${tor.status} onion in the invite=${derived != null}');
    final socket = getIt<NoxSocketClient>();
    final selector = getIt<ConnectionPathSelector>();
    final rssBefore = ProcessInfo.currentRss;

    final watch = Stopwatch()..start();
    final signedIn = await getIt<AuthRepository>().signIn(identifier: link);
    debugPrint('MEASURE: paired at home in ${watch.elapsedMilliseconds} ms (${signedIn.hasData ? 'ok' : signedIn.exception})');
    expect(signedIn.hasData, isTrue, reason: 'the pairing, directly');
    await _until('live directly', const Duration(seconds: 30), () {
      return socket.currentPhase == SessionPhase.live && selector.currentPath == ConnectionPath.direct;
    });
    // Tor only by the person's leave (phase 045).
    expect((await getIt<ServerAddressesRepository>().setUseTor(true)).hasData, isTrue);
    await _until('the onion address known', const Duration(minutes: 5), () async {
      return (await getIt<ServerAddressesRepository>().read()).data?.onion != null;
    });

    // Away from home: no direct address answers any more.
    away.away = true;
    watch.reset();
    await socket.reconnect();
    await _until('live through Tor on its own key', const Duration(minutes: 4), () {
      return socket.currentPhase == SessionPhase.live && selector.currentPath == ConnectionPath.tor;
    });
    debugPrint('MEASURE: live through Tor ${watch.elapsedMilliseconds} ms after leaving home');

    final chat = await getIt<ChatRepository>().createChat(
      name: 'From ${Platform.operatingSystem} ${DateTime.now().millisecondsSinceEpoch}',
    );
    expect(chat.hasData, isTrue);
    final sendWatch = Stopwatch()..start();
    final sent = await getIt<MessageRepository>().sendMessage(
      chatId: chat.data!.id,
      clientMessageId: const Uuid().v4(),
      text: 'hello through Tor from ${Platform.operatingSystem}',
    );
    debugPrint('MEASURE: a message through Tor in ${sendWatch.elapsedMilliseconds} ms');
    expect(sent.hasData, isTrue);
    debugPrint(
      'MEASURE: RSS ${(rssBefore / 1048576).toStringAsFixed(1)} MB before, '
      '${(ProcessInfo.currentRss / 1048576).toStringAsFixed(1)} MB on Tor',
    );

    // A fresh invite from THIS device, so the next platform's run does not
    // depend on a ten-minute window opened elsewhere. It pairs at home only,
    // and says so, until phase 045.
    final next = await getIt<DeviceRepository>().inviteDevice();
    expect(next.data?.onion, isFalse, reason: 'a new device pairs at home until phase 045');
    debugPrint('NEXT_INVITE: ${next.data?.link}');
  }, timeout: const Timeout(Duration(minutes: 12)));
}

Future<void> _until(String what, Duration budget, FutureOr<bool> Function() done) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < budget) {
    if (await done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('not reached within ${budget.inSeconds} s: $what');
}
