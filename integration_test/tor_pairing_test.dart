import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:integration_test/integration_test.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/sync/connection/connection_path_selector.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_app/domain/model/connection/connection_path.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/connection/access_key_repository.dart';
import 'package:nox_app/domain/repository/device/device_repository.dart';
import 'package:nox_app/domain/service/tor_service.dart';
import 'package:nox_app/general/pairing/pairing_link.dart';
import 'package:uuid/uuid.dart';

/// Device B of the phase 040 quickstart, scenario 5, on a simulator or an
/// emulator: a version-2 invite pairs THROUGH TOR with the one-time key it
/// lends, and the device then talks to its server over its own key (US4,
/// FR-020, FR-021). The Tor client is the real one, in the app's process on
/// that platform.
///
/// Manual, like the live probes: it needs a running `noxd` with tor and a fresh
/// invite - `test/live/tor_live_probe.dart` leaves both behind:
///   fvm flutter test integration_test/tor_pairing_test.dart -d DEVICE \
///     --dart-define=link=V2_INVITE --dart-define=nox.forceTor=true
///
/// `nox.forceTor` (debug builds only) skips the direct address, so the pairing
/// goes through Tor even where the server would answer directly.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const link = String.fromEnvironment('link');

  testWidgets('a version-2 invite pairs through Tor, and the device then talks over its own key', (tester) async {
    if (link.isEmpty) {
      debugPrint('SKIP: pass --dart-define=link=<version-2 invite>');
      return;
    }
    await configureDependencies(Environment.dev);
    await getIt.allReady();
    await getIt<AppConfigRepository>().initialize(flavorType: AppFlavorType.stage);
    final tor = getIt<TorService>();
    final lent = PairingLink.parse(link);
    debugPrint('TOR: supported=${tor.isSupported} status=${tor.status} invite-onion=${lent.carriesOnion}');
    final derived = tor.onionFromPublicKey(lent.onionPub!);
    debugPrint('TOR: onion derived=${derived != null} (${derived?.length ?? 0} chars)');
    final socket = getIt<NoxSocketClient>();
    final selector = getIt<ConnectionPathSelector>();
    final rssBefore = ProcessInfo.currentRss;

    final watch = Stopwatch()..start();
    final signedIn = await getIt<AuthRepository>().signIn(identifier: link);
    debugPrint('MEASURE: paired through Tor in ${watch.elapsedMilliseconds} ms (${signedIn.hasData ? 'ok' : signedIn.exception})');
    expect(signedIn.hasData, isTrue, reason: 'the pairing through Tor');

    await _until('live through Tor on its own key', const Duration(minutes: 4), () {
      return socket.currentPhase == SessionPhase.live && selector.currentPath == ConnectionPath.tor;
    });
    debugPrint('MEASURE: live through Tor ${watch.elapsedMilliseconds} ms after the start');
    expect((await getIt<AccessKeyRepository>().isRegistered()).data, isTrue, reason: 'the key went in with the pairing');

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
    // depend on a ten-minute window opened elsewhere.
    final next = await getIt<DeviceRepository>().inviteDevice();
    expect(next.data?.onion, isTrue, reason: 'an invite asked through Tor carries the onion address too');
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
