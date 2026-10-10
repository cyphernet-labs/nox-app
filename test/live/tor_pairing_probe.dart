@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/service/network_change_service_impl.dart';
import 'package:nox_app/data/sync/connection/connection_path_selector.dart';
import 'package:nox_app/data/sync/connection/direct_prober.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/connection/connection_path.dart';
import 'package:nox_app/general/pairing/pairing_link.dart';
import 'package:nox_app/domain/service/tor_service.dart';
import 'package:nox_app/domain/model/connection/connection_settings.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/service/network_change_service.dart';
import 'package:nox_tor/channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'live_harness.dart';
import 'live_target.dart';

/// Device B on this machine, as phase 045 has it: away from home - no direct
/// address answers - an invite carrying the onion address pairs THROUGH TOR,
/// with `Use Tor` ticked on the connection screen, and the device then talks
/// through Tor. No access key anywhere. The macOS twin of
/// integration_test/tor_pairing_test.dart; `tor_live_probe.dart` leaves the
/// server, its tor and two invites behind.
///   fvm flutter test test/live/tor_pairing_probe.dart --dart-define=link=INVITE
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const link = String.fromEnvironment('link');

  test(
    'away from home, an invite pairs through Tor with Use Tor on, and the device talks through Tor (phase 045)',
    () async {
      if (link.isEmpty) {
        stdout.writeln('SKIP: pass --dart-define=link=<nox://pair/ invite>');
        return;
      }
      LiveTarget.letTheNetworkThrough();
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      await configureDependencies(Environment.dev);
      await getIt.allReady();
      // No platform plugins on the host: the network watch is not what this
      // probe is about. And "away" comes from a prober that can be told so.
      getIt.allowReassignment = true;
      getIt.registerSingleton<NetworkChangeService>(QuietNetworkChangeService());
      final away = AwayProber(ChannelDirectProber(const NativeNoxChannelApi()))..away = true;
      getIt.registerSingleton<DirectProber>(away);

      final invite = PairingLink.parse(link);
      final serviceKey = invite.onionServiceKey;
      expect(serviceKey, isNotNull, reason: 'an invite from a server with an onion address carries it');
      final onion = getIt<TorService>().onionFromPublicKey(serviceKey!);

      final watch = Stopwatch()..start();
      final signedIn = await getIt<AuthRepository>().signIn(
        identifier: link,
        connection: ConnectionSettings(serverAddress: invite.directAddresses.first, onionAddress: '$onion:443', useTor: true),
      );
      stdout.writeln('MEASURE: paired through Tor: ${signedIn.hasData ? 'ok' : signedIn.exception} after ${watch.elapsedMilliseconds} ms');
      expect(signedIn.hasData, isTrue);

      final socket = getIt<NoxSocketClient>();
      final selector = getIt<ConnectionPathSelector>();
      await liveUntil('live through Tor', const Duration(minutes: 4), () {
        return socket.currentPhase == SessionPhase.live && selector.currentPath == ConnectionPath.tor;
      });
      stdout.writeln('MEASURE: live through Tor ${watch.elapsedMilliseconds} ms after the start');
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
