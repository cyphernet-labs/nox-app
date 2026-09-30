import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/service/tor/native_tor_service.dart';
import 'package:nox_app/data/service/tor/nox_tor_api.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/connection/tor_status.dart';
import 'package:nox_tor/nox_tor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The native library and the network behind it, scripted.
class _FakeApi extends NoxTorApi {
  NoxTorSnapshot snapshot = NoxTorSnapshot.stopped;
  int starts = 0;
  int stops = 0;
  ({String host, int port})? target;

  @override
  void start({required String stateDir, required String cacheDir}) {
    starts++;
    snapshot = const NoxTorSnapshot(state: NoxTorState.bootstrapping, bootstrapPercent: 10, error: NoxTorError.none, port: null);
  }

  @override
  void stop() {
    stops++;
    snapshot = NoxTorSnapshot.stopped;
  }

  @override
  void setTarget({required String onionHost, required int port, required Uint8List clientKey}) {
    target = (host: onionHost, port: port);
    snapshot = NoxTorSnapshot(state: snapshot.state, bootstrapPercent: snapshot.bootstrapPercent, error: snapshot.error, port: 4242);
  }

  @override
  void clearTarget() => target = null;

  @override
  void setDormant(bool dormant) {}

  @override
  NoxTorSnapshot status() => snapshot;

  @override
  Uint8List bridgeSecret() => Uint8List.fromList(List<int>.filled(32, 9));

  @override
  String onionFromPublicKey(Uint8List publicKey) => 'x.onion';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late _FakeApi api;
  late NativeTorService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    prefs = await SharedPreferences.getInstance();
    api = _FakeApi();
    service = NativeTorService.forTest(prefs, api: api, directories: () async => ('/s', '/c'), build: () async => '42');
  });

  tearDown(() async {
    await service.stop();
    await getIt.reset();
  });

  test('start brings the client up and the status follows the snapshot', () async {
    await service.start();
    expect(api.starts, 1);
    expect(service.status.state, TorState.bootstrapping);
    expect(service.status.bootstrapPercent, 10);
  });

  test('a target opens the bridge with its secret, read once at set time', () async {
    await service.start();
    service.setTarget(onionHost: 'x.onion', port: 443, clientKey: Uint8List(32));
    expect(api.target, (host: 'x.onion', port: 443));
    expect(service.bridge?.port, 4242);
    expect(service.bridge?.secret, Uint8List.fromList(List<int>.filled(32, 9)));
    service.clearTarget();
    expect(service.bridge, isNull);
  });

  test('obsolete is remembered for this build, and this build does not start Tor again', () async {
    await service.start();
    api.snapshot = const NoxTorSnapshot(
      state: NoxTorState.obsolete,
      bootstrapPercent: 0,
      error: NoxTorError.softwareDeprecated,
      port: null,
    );
    service.setDormant(false); // any call polls the snapshot
    await pumpEventQueue();
    expect(prefs.getString(NativeTorService.kObsoleteBuild), '42');

    final again = NativeTorService.forTest(prefs, api: _FakeApi(), directories: () async => ('/s', '/c'), build: () async => '42');
    await again.start();
    expect(again.status.isObsolete, isTrue);

    final nextBuild = _FakeApi();
    final updated = NativeTorService.forTest(prefs, api: nextBuild, directories: () async => ('/s', '/c'), build: () async => '43');
    await updated.start();
    expect(nextBuild.starts, 1, reason: 'a new build tries again');
    await again.stop();
    await updated.stop();
  });

  test('an unsupported platform does nothing at all', () async {
    final linux = NativeTorService.forTest(
      prefs,
      api: api,
      directories: () async => ('/s', '/c'),
      build: () async => '42',
      supported: false,
    );
    await linux.start();
    linux.setTarget(onionHost: 'x.onion', port: 443, clientKey: Uint8List(32));
    expect(api.starts, 0);
    expect(api.target, isNull);
    expect(linux.onionFromPublicKey(Uint8List(32)), isNull);
  });
}
