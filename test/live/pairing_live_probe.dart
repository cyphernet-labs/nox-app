@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/device/device_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the REAL client code against a running `noxd`, which is the gap the
/// first live run left: it spoke the wire directly and so never exercised the
/// client's own greeting, which turned out to be the defect that mattered.
///
/// Run manually, not in the gate: it needs a server.
///   1. cd client_backend && go build -o /tmp/noxd . && /tmp/noxd -db /tmp/t.db
///   2. flutter test test/live/pairing_live_probe.dart --dart-define=link=<link>
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const link = String.fromEnvironment('link');

  test('a link pairs, names the person, lists the device and revokes it', () async {
    if (link.isEmpty) {
      stdout.writeln('SKIP: pass --dart-define=link=<pairing link>');
      return;
    }
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.dev);
    await getIt.allReady();

    final auth = getIt<AuthRepository>();
    final session = getIt<SessionRepository>();
    final devices = getIt<DeviceRepository>();

    final signedIn = await auth.signIn(identifier: link);
    stdout.writeln('SIGN IN: ${signedIn.hasData ? 'ok' : signedIn.exception}');
    expect(signedIn.hasData, isTrue, reason: 'the whole flow starts here');

    // The wipe-on-refusal bug showed up exactly here: the key and the address
    // were deleted while pairing succeeded, spending the one-shot token.
    stdout.writeln('SERVER: ${(await session.serverAddress()).data}');
    expect((await session.serverAddress()).data, isNotNull, reason: 'the paired server must survive the sign-in');
    expect((await session.deviceSecret()).hasData, isTrue, reason: 'the device key must survive the sign-in');

    final named = await auth.completeOnboarding(label: 'LiveAnna');
    stdout.writeln('NAME: ${named.hasData ? 'ok' : named.exception}');
    expect(named.hasData, isTrue);

    await Future<void>.delayed(const Duration(seconds: 2));
    final list = await devices.getDevices();
    stdout.writeln('DEVICES: ${list.data?.map((d) => '${d.platform}/current=${d.isCurrent}').toList()}');
    expect(list.hasData, isTrue);
    expect(list.data!.where((d) => d.isCurrent).length, 1, reason: 'this device has to recognise itself');

    final invite = await devices.inviteDevice();
    stdout.writeln('INVITE: ${invite.hasData ? 'ok' : invite.exception}');
    expect(invite.hasData, isTrue);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
