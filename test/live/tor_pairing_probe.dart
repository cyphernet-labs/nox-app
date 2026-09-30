@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/sync/connection/connection_path_selector.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/connection/connection_path.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'live_target.dart';

/// Device B of quickstart scenario 5 on this machine: a version-2 invite pairs
/// through Tor with its one-time key, and the device then connects on its own
/// key. The macOS twin of integration_test/tor_pairing_test.dart.
///   fvm flutter test test/live/tor_pairing_probe.dart --dart-define=link=V2_INVITE --dart-define=nox.forceTor=true
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const link = String.fromEnvironment('link');

  test('a version-2 invite pairs through Tor and the device then connects on its own key', () async {
    if (link.isEmpty) {
      stdout.writeln('SKIP: pass --dart-define=link=<version-2 invite>');
      return;
    }
    LiveTarget.letTheNetworkThrough();
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(appName: 'nox', packageName: 'nox', version: '0', buildNumber: 'b', buildSignature: '');
    await configureDependencies(Environment.dev);
    await getIt.allReady();

    final watch = Stopwatch()..start();
    final signedIn = await getIt<AuthRepository>().signIn(identifier: link);
    stdout.writeln('MEASURE: sign-in ${signedIn.hasData ? 'ok' : signedIn.exception} after ${watch.elapsedMilliseconds} ms');
    expect(signedIn.hasData, isTrue);

    final socket = getIt<NoxSocketClient>();
    final selector = getIt<ConnectionPathSelector>();
    final until = Stopwatch()..start();
    while (!(socket.currentPhase == SessionPhase.live && selector.currentPath == ConnectionPath.tor)) {
      if (until.elapsed > const Duration(minutes: 4)) fail('never live through Tor on its own key');
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    stdout.writeln('MEASURE: live through Tor on its own key ${watch.elapsedMilliseconds} ms after the start');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
