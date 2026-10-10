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
import 'package:nox_app/domain/model/connection/connection_settings.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
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

/// Device B on a simulator or an emulator, as phase 045 has it: away from
/// home - no direct address answers - an invite carrying the onion address
/// pairs THROUGH TOR, with `Use Tor` ticked on the connection screen, and the
/// device talks to its server through Tor. No access key anywhere. The Tor
/// client and the channel are the real ones, in the app's process on that
/// platform.
///
/// Manual, like the live probes: it needs a running `noxd` whose onion
/// service a separate tor publishes, and a fresh invite -
/// `test/live/tor_live_probe.dart` leaves all three behind:
///   fvm flutter test integration_test/tor_pairing_test.dart -d DEVICE --dart-define=link=INVITE
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const link = String.fromEnvironment('link');

  testWidgets('away from home, an invite pairs through Tor with Use Tor on, and the device talks through Tor', (tester) async {
    if (link.isEmpty) {
      debugPrint('SKIP: pass --dart-define=link=<nox://pair/ invite>');
      return;
    }
    await configureDependencies(Environment.dev);
    await getIt.allReady();
    await getIt<AppConfigRepository>().initialize(flavorType: AppFlavorType.stage);
    // Registered before anything resolves the path selector.
    getIt.allowReassignment = true;
    final away = _AwayProber(ChannelDirectProber(const NativeNoxChannelApi()))..away = true;
    getIt.registerSingleton<DirectProber>(away);
    final tor = getIt<TorService>();
    final invite = PairingLink.parse(link);
    final serviceKey = invite.onionServiceKey;
    final derived = serviceKey == null ? null : tor.onionFromPublicKey(serviceKey);
    debugPrint('TOR: supported=${tor.isSupported} status=${tor.status} onion in the invite=${derived != null}');
    final socket = getIt<NoxSocketClient>();
    final selector = getIt<ConnectionPathSelector>();
    final rssBefore = ProcessInfo.currentRss;

    expect(derived, isNotNull, reason: 'the invite names the onion service, and the module derives its address');

    final watch = Stopwatch()..start();
    // As the connection screen hands it over: the link's addresses, and Use
    // Tor ticked (phase 045).
    final signedIn = await getIt<AuthRepository>().signIn(
      identifier: link,
      connection: ConnectionSettings(serverAddress: invite.directAddresses.first, onionAddress: '$derived:443', useTor: true),
    );
    debugPrint('MEASURE: paired through Tor in ${watch.elapsedMilliseconds} ms (${signedIn.hasData ? 'ok' : signedIn.exception})');
    expect(signedIn.hasData, isTrue, reason: 'the pairing, through Tor');
    await _until('live through Tor', const Duration(minutes: 4), () {
      return socket.currentPhase == SessionPhase.live && selector.currentPath == ConnectionPath.tor;
    });
    debugPrint('MEASURE: live through Tor ${watch.elapsedMilliseconds} ms after the start');

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
    // depend on a ten-minute window opened elsewhere. It carries the onion
    // address, so the next device pairs through Tor too (phase 045).
    final next = await getIt<DeviceRepository>().inviteDevice();
    expect(next.data?.onion, isTrue, reason: 'issued through Tor, and carrying the onion address');
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
