@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/remote/socket/server_frame.dart';
import 'package:nox_app/data/service/network_change_service_impl.dart';
import 'package:nox_app/data/sync/connection/connection_path_selector.dart';
import 'package:nox_app/data/sync/connection/direct_prober.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/connection/connection_path.dart';
import 'package:nox_app/domain/model/connection/connection_settings.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/service/network_change_service.dart';
import 'package:nox_app/domain/service/tor_service.dart';
import 'package:nox_app/general/pairing/pairing_link.dart';
import 'package:nox_app/general/platform_utils.dart';
import 'package:nox_tor/channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'live_harness.dart';
import 'live_target.dart';

/// Device B on this machine, as phases 045 and 046 have it: away from home -
/// no direct address answers - an invite carrying the onion address pairs
/// THROUGH TOR, with `Use Tor` ticked on the connection screen, once the
/// device that issued it says Allow; the device then talks through Tor. No
/// access key anywhere. The macOS twin of
/// integration_test/tor_pairing_test.dart.
///
/// An invite pairs nothing until the device that issued it allows it (phase
/// 046), so the probe brings that device itself ([WireDevice]): paired at home
/// by a machine link, it issues the invite and answers the request. Every run
/// takes a fresh machine link; `tor_live_probe.dart` leaves the server, its
/// tor and the service page's address behind:
///   fvm flutter test test/live/tor_pairing_probe.dart \
///     --dart-define=link="$(/tmp/noxd link -status-addr "$(cat /tmp/nox_e2e/page.txt)" | head -1)"
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const link = String.fromEnvironment('link');

  test(
    'away from home, an invite pairs through Tor with Use Tor on once its device allows it, and the device talks through Tor',
    () async {
      if (link.isEmpty) {
        stdout.writeln('SKIP: pass --dart-define=link=<a machine link: noxd\'s service page, or `noxd link`>');
        return;
      }
      LiveTarget.letTheNetworkThrough();
      expect(PairingLink.parse(link).onionServiceKey, isNotNull, reason: 'a link from a server with an onion address carries it');
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

      // --- The issuing device, at home: paired by the machine link, it
      // issues the invite this device then pairs by. ---
      final issuer = await WireDevice.paired(link, platform: 'linux');
      addTearDown(issuer.close);
      final inviteLink = await issuer.invite();
      final invite = PairingLink.parse(inviteLink);
      final serviceKey = invite.onionServiceKey;
      expect(serviceKey, isNotNull, reason: 'an invite from a server with an onion address carries it');
      final onion = getIt<TorService>().onionFromPublicKey(serviceKey!);

      // --- This device, away: the request reaches the issuing device once it
      // got through Tor, and the sign-in waits for the answer. ---
      final asked = issuer.next(ServerEvent.devicePairRequested, within: const Duration(minutes: 8));
      final watch = Stopwatch()..start();
      final signingIn = getIt<AuthRepository>().signIn(
        identifier: inviteLink,
        connection: ConnectionSettings(serverAddress: invite.directAddresses.first, onionAddress: '$onion:443', useTor: true),
      );
      final first = await Future.any<Object>([asked, signingIn]);
      if (first is! ServerEvent) {
        asked.ignore();
        fail('the sign-in ended before the issuing device was asked: ${(first as RepositoryResult<bool>).exception}');
      }
      stdout.writeln('MEASURE: asked on the issuing device ${watch.elapsedMilliseconds} ms after the start');
      expect(first.data['platform'], PlatformUtils.family, reason: 'the question names the family this device gave');
      expect(await issuer.approve(first.data['request_id'] as String, allow: true), isTrue);
      final signedIn = await signingIn;
      stdout.writeln('MEASURE: paired through Tor: ${signedIn.hasData ? 'ok' : signedIn.exception} after ${watch.elapsedMilliseconds} ms');
      expect(signedIn.hasData, isTrue);

      final socket = getIt<NoxSocketClient>();
      final selector = getIt<ConnectionPathSelector>();
      await liveUntil('live through Tor', const Duration(minutes: 4), () {
        return socket.currentPhase == SessionPhase.live && selector.currentPath == ConnectionPath.tor;
      });
      stdout.writeln('MEASURE: live through Tor ${watch.elapsedMilliseconds} ms after the start');
    },
    timeout: const Timeout(Duration(minutes: 14)),
  );
}
