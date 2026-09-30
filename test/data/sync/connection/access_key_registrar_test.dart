import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/sync/connection/access_key_registrar.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/connection/access_key_repository.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../remote/socket/fake_socket.dart';

/// Registering this device's onion access key on the server (phase 040,
/// FR-016, FR-017), over a real socket client and an in-memory peer.
void main() {
  late FakeSocketFactory factory;
  late NoxSocketClient socket;
  late AccessKeyRepository keys;
  late AccessKeyRegistrar registrar;

  final url = Uri.parse('wss://10.0.0.5:9000/ws');

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase();
    factory = FakeSocketFactory();
    socket = NoxSocketClient(factory, getIt<SyncRepository>());
    keys = getIt<AccessKeyRepository>();
    registrar = AccessKeyRegistrar(socket, keys)..start();
  });

  tearDown(() async {
    await registrar.stop();
    await socket.stop();
    await getIt.reset();
  });

  Future<void> waitUntil(FutureOr<bool> Function() done, {String reason = ''}) async {
    for (var i = 0; i < 400; i++) {
      if (await done()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('condition never became true${reason.isEmpty ? '' : ': $reason'}');
  }

  /// Greets, with or without the support flag (`addresses`).
  Future<FakeSocket> greet({required bool supportsKeys}) async {
    await socket.start(url: url, credentialsProvider: () async => const GreetingCredentials());
    final peer = factory.latest;
    peer.pushGreeting();
    await waitUntil(() => peer.commandNamed('session.hello') != null, reason: 'the client greets back');
    peer.reply(
      peer.sent.indexWhere((f) => f['cmd'] == 'session.hello'),
      data: {
        'schema': 1,
        'cursor': 0,
        'journal_id': 'j_test',
        'identity': {'id': 'u_1', 'label': 'Anna'},
        if (supportsKeys) 'addresses': {'direct': <String>[]},
      },
    );
    await waitUntil(() => socket.currentPhase == SessionPhase.live, reason: 'greeted');
    return peer;
  }

  List<Map<String, dynamic>> setKeyCommands(FakeSocket peer) => peer.sent.where((f) => f['cmd'] == 'device.setAccessKey').toList();

  test('a server that reads keys gets this device key, and it is then registered', () async {
    final peer = await greet(supportsKeys: true);
    await waitUntil(() => setKeyCommands(peer).isNotEmpty, reason: 'the key is sent');

    final own = (await keys.deviceKey()).data!;
    expect((setKeyCommands(peer).single['data'] as Map<String, dynamic>)['access_key'], own.publicBase64);
    peer.reply(peer.sent.indexOf(setKeyCommands(peer).single), data: const <String, dynamic>{});

    await waitUntil(() async => (await keys.isRegistered()).data ?? false, reason: 'registered on success');
  });

  test('a server older than 039 is not sent a command it does not know (contract §2.1)', () async {
    final peer = await greet(supportsKeys: false);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(setKeyCommands(peer), isEmpty);
  });

  test('a key already registered is not sent again', () async {
    await keys.markRegistered(true);
    final peer = await greet(supportsKeys: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(setKeyCommands(peer), isEmpty);
  });

  test('a key the onion service turned away is offered again at the next greeting (T039)', () async {
    // The path selector marks the key unregistered when Tor reports that the
    // service does not know it; the next direct greeting puts it back.
    await keys.markRegistered(true);
    await keys.markRegistered(false);

    final peer = await greet(supportsKeys: true);

    await waitUntil(() => setKeyCommands(peer).isNotEmpty, reason: 'offered again');
  });

  test('a refused key is replaced and offered again, no more than three times (FR-017)', () async {
    final peer = await greet(supportsKeys: true);
    final offered = <String>{};
    for (var i = 0; i <= AccessKeyRegistrar.maxNewKeys; i++) {
      await waitUntil(() => setKeyCommands(peer).length > i, reason: 'attempt ${i + 1}');
      final command = setKeyCommands(peer)[i];
      offered.add((command['data'] as Map<String, dynamic>)['access_key'] as String);
      peer.reply(peer.sent.indexOf(command), ok: false, code: 'invalid_request');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(setKeyCommands(peer), hasLength(AccessKeyRegistrar.maxNewKeys + 1), reason: 'the first key and three new ones');
    expect(offered, hasLength(AccessKeyRegistrar.maxNewKeys + 1), reason: 'each one a different key');
    expect((await keys.isRegistered()).data, isFalse);
  });

  test('a revoked device is left to the revocation path', () async {
    final peer = await greet(supportsKeys: true);
    await waitUntil(() => setKeyCommands(peer).isNotEmpty, reason: 'the key is sent');
    final before = (await keys.deviceKey()).data!.publicBase64;

    peer.reply(peer.sent.indexOf(setKeyCommands(peer).single), ok: false, code: 'unauthenticated');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(setKeyCommands(peer), hasLength(1), reason: 'no new key for a device that is gone');
    expect((await keys.deviceKey()).data!.publicBase64, before);
  });
}
