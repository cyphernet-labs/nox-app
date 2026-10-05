import 'dart:async';
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
  String clientVersion = 'arti-client 0.47.0';

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

  @override
  String version() => clientVersion;
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
    service = NativeTorService.forTest(prefs, api: api, directories: () async => ('/s', '/c'));
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

  test('obsolete is remembered for this Tor client, and the same client is not started again', () async {
    await service.start();
    api.snapshot = const NoxTorSnapshot(
      state: NoxTorState.obsolete,
      bootstrapPercent: 0,
      error: NoxTorError.softwareDeprecated,
      port: null,
    );
    service.setDormant(false); // any call polls the snapshot
    await pumpEventQueue();
    expect(prefs.getString(NativeTorService.kObsoleteClient), 'arti-client 0.47.0');

    final again = NativeTorService.forTest(prefs, api: _FakeApi(), directories: () async => ('/s', '/c'));
    await again.start();
    expect(again.status.isObsolete, isTrue, reason: 'an update with the same client would be refused again');

    final nextBuild = _FakeApi()..clientVersion = 'arti-client 0.48.0';
    final updated = NativeTorService.forTest(prefs, api: nextBuild, directories: () async => ('/s', '/c'));
    await updated.start();
    expect(nextBuild.starts, 1, reason: 'a newer client tries again');
    await again.stop();
    await updated.stop();
  });

  test('a stop while the directories are looked up keeps the client down', () async {
    // A logout wipes the directories right after the stop; a start that went
    // ahead would bring Tor up for nobody and write them back.
    final directories = Completer<(String, String)>();
    final racing = NativeTorService.forTest(prefs, api: api, directories: () => directories.future);
    final starting = racing.start();
    await racing.stop();
    directories.complete(('/s', '/c'));
    await starting;

    expect(api.starts, 0);
  });

  test('a client gone without a port takes its bridge with it', () async {
    await service.start();
    service.setTarget(onionHost: 'x.onion', port: 443, clientKey: Uint8List(32));
    expect(service.bridge, isNotNull);

    // Refused as obsolete: the library tears itself down, listener and all.
    api.snapshot = const NoxTorSnapshot(
      state: NoxTorState.obsolete,
      bootstrapPercent: 0,
      error: NoxTorError.softwareDeprecated,
      port: null,
    );
    service.setDormant(false); // any call polls the snapshot
    await pumpEventQueue();

    expect(service.bridge, isNull, reason: 'the port may belong to somebody else by the next dial');
  });

  test('an unsupported platform does nothing at all', () async {
    final linux = NativeTorService.forTest(prefs, api: api, directories: () async => ('/s', '/c'), supported: false);
    await linux.start();
    linux.setTarget(onionHost: 'x.onion', port: 443, clientKey: Uint8List(32));
    expect(api.starts, 0);
    expect(api.target, isNull);
    expect(linux.onionFromPublicKey(Uint8List(32)), isNull);
  });
}
