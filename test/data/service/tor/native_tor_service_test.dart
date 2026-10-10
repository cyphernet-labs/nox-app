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
  String clientVersion = 'arti-client 0.47.0';

  @override
  void start({required String stateDir, required String cacheDir}) {
    starts++;
    snapshot = const NoxTorSnapshot(state: NoxTorState.bootstrapping, bootstrapPercent: 10, error: NoxTorError.none);
  }

  @override
  void stop() {
    stops++;
    snapshot = NoxTorSnapshot.stopped;
  }

  @override
  void setDormant(bool dormant) {}

  @override
  NoxTorSnapshot status() => snapshot;

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

  test('the access-key codes the ABI keeps in its numbering read as nothing gone wrong (phase 045)', () async {
    // The client holds no access keys, so the module never reports them; a
    // status carrying one says nothing the app has a kind for.
    await service.start();
    api.snapshot = const NoxTorSnapshot(state: NoxTorState.ready, bootstrapPercent: 100, error: NoxTorError.wrongClientAuth);
    service.setDormant(false); // any call polls the snapshot
    await pumpEventQueue();
    expect(service.status.error, TorError.none);
    expect(service.status.isReady, isTrue);
  });

  test('every other error kind of the module keeps its meaning', () {
    expect(NativeTorService.errorOf(NoxTorError.none), TorError.none);
    expect(NativeTorService.errorOf(NoxTorError.timeout), TorError.timeout);
    expect(NativeTorService.errorOf(NoxTorError.network), TorError.network);
    expect(NativeTorService.errorOf(NoxTorError.internal), TorError.internal);
    expect(NativeTorService.errorOf(NoxTorError.softwareDeprecated), TorError.softwareDeprecated);
    expect(NativeTorService.errorOf(NoxTorError.missingClientAuth), TorError.none);
  });

  test('obsolete is remembered for this Tor client, and the same client is not started again', () async {
    await service.start();
    api.snapshot = const NoxTorSnapshot(state: NoxTorState.obsolete, bootstrapPercent: 0, error: NoxTorError.softwareDeprecated);
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

  test('where Tor is not supported none runs, but an onion address still reads', () async {
    // The address is the module's arithmetic, and asking it costs nothing
    // even where Tor itself does not run.
    final unsupported = NativeTorService.forTest(prefs, api: api, directories: () async => ('/s', '/c'), supported: false);
    await unsupported.start();
    expect(api.starts, 0);
    expect(unsupported.onionFromPublicKey(Uint8List(32)), 'x.onion');
  });
}
