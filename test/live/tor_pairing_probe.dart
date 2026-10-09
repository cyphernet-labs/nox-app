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
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/connection/access_key_repository.dart';
import 'package:nox_app/domain/repository/connection/server_addresses_repository.dart';
import 'package:nox_app/domain/service/network_change_service.dart';
import 'package:nox_tor/channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'live_harness.dart';
import 'live_target.dart';

/// Device B of quickstart scenario 5 on this machine, as phase 044 leaves it:
/// an invite pairs at home, directly - the onion service opens only for a
/// paired device's key until phase 045 - and the device then goes away and
/// connects through Tor on its own key. The macOS twin of
/// integration_test/tor_pairing_test.dart.
///   fvm flutter test test/live/tor_pairing_probe.dart --dart-define=link=INVITE
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const link = String.fromEnvironment('link');

  test('an invite pairs at home, and the device then connects through Tor on its own key', () async {
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
    final away = AwayProber(ChannelDirectProber(const NativeNoxChannelApi()));
    getIt.registerSingleton<DirectProber>(away);

    final watch = Stopwatch()..start();
    final signedIn = await getIt<AuthRepository>().signIn(identifier: link);
    stdout.writeln('MEASURE: sign-in ${signedIn.hasData ? 'ok' : signedIn.exception} after ${watch.elapsedMilliseconds} ms');
    expect(signedIn.hasData, isTrue);

    final socket = getIt<NoxSocketClient>();
    final selector = getIt<ConnectionPathSelector>();
    await liveUntil('the access key registered', const Duration(seconds: 30), () async {
      return (await getIt<AccessKeyRepository>().isRegistered()).data ?? false;
    });
    await liveUntil('the onion address known', const Duration(minutes: 5), () async {
      return (await getIt<ServerAddressesRepository>().read()).data?.onion != null;
    });

    away.away = true;
    await socket.reconnect();
    await liveUntil('live through Tor on its own key', const Duration(minutes: 4), () {
      return socket.currentPhase == SessionPhase.live && selector.currentPath == ConnectionPath.tor;
    });
    stdout.writeln('MEASURE: live through Tor on its own key ${watch.elapsedMilliseconds} ms after the start');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
