import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/sync/pair_request_service_impl.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/device/pair_request.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/log_repository.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../remote/socket/fake_socket.dart';

/// The issuing device's side of pairing with approval (phase 046, contract
/// §8A), driven over a real socket and an in-memory peer.
void main() {
  late FakeSocketFactory factory;
  late NoxSocketClient client;
  late PairRequestServiceImpl service;

  final url = Uri.parse('ws://127.0.0.1:8080/ws');

  Future<void> waitUntil(FutureOr<bool> Function() done, {String reason = ''}) async {
    for (var i = 0; i < 400; i++) {
      if (await done()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('condition never became true${reason.isEmpty ? '' : ': $reason'}');
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase();
    factory = FakeSocketFactory();
    client = NoxSocketClient.forTest(factory, getIt<SyncRepository>(), minBackoff: const Duration(milliseconds: 10));
    service = PairRequestServiceImpl(client);
  });

  tearDown(() async {
    await service.dispose();
    await client.stop();
    await getIt.reset();
  });

  /// A paired device, greeted.
  Future<FakeSocket> greeted() async {
    await client.start(url: url, credentialsProvider: () async => const GreetingCredentials());
    final socket = factory.latest;
    socket.pushGreeting();
    await waitUntil(() => socket.commandNamed('session.hello') != null, reason: 'greets');
    socket.replyToHello(cursor: 0);
    await waitUntil(() => client.currentPhase == SessionPhase.live, reason: 'live');
    return socket;
  }

  void asked(FakeSocket socket, {String id = 'r_1', Object? platform = 'windows'}) =>
      socket.pushEvent(seq: 0, event: 'device.pairRequested', data: {'request_id': id, 'platform': platform, 'expires_at': 1790000600});

  int last(FakeSocket socket, String cmd) => socket.sent.lastIndexWhere((f) => f['cmd'] == cmd);

  test('a request is put up with the new device\'s family and deadline, and nothing else', () async {
    final socket = await greeted();

    asked(socket);
    await waitUntil(() => service.watchRequests().first.then((r) => r.isNotEmpty), reason: 'asked');

    final request = (await service.watchRequests().first).single;
    expect(
      request,
      PairRequest(
        requestId: 'r_1',
        platform: DevicePlatform.windows,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(1790000600 * 1000, isUtc: true),
      ),
    );
  });

  test('the same request asked again after a greeting is still one request', () async {
    final socket = await greeted();

    asked(socket);
    asked(socket);
    asked(socket, id: 'r_2', platform: 'ios');
    await waitUntil(() => service.watchRequests().first.then((r) => r.length == 2), reason: 'two asked');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect((await service.watchRequests().first).map((r) => r.requestId), ['r_1', 'r_2'], reason: 'oldest first, no duplicate');
  });

  for (final (wire, family) in [
    ('ios', DevicePlatform.ios),
    ('android', DevicePlatform.android),
    ('macos', DevicePlatform.macos),
    ('windows', DevicePlatform.windows),
    ('linux', DevicePlatform.linux),
    ('iPhone 15 Pro (Anna)', DevicePlatform.unknown),
    (42, DevicePlatform.unknown),
    (null, DevicePlatform.unknown),
  ]) {
    test('"$wire" from the wire is shown as ${family.name} - never as the text itself', () async {
      final socket = await greeted();

      asked(socket, platform: wire);
      await waitUntil(() => service.watchRequests().first.then((r) => r.isNotEmpty), reason: 'asked');

      expect((await service.watchRequests().first).single.platform, family);
    });
  }

  test('a request that closes, any way, is taken down and reported over', () async {
    final socket = await greeted();
    final closed = <String>[];
    final sub = service.watchClosed().listen(closed.add);
    addTearDown(sub.cancel);
    asked(socket);
    await waitUntil(() => service.watchRequests().first.then((r) => r.isNotEmpty), reason: 'asked');

    socket.pushEvent(seq: 0, event: 'device.pairResolved', data: const {'request_id': 'r_1'});
    await waitUntil(() => closed.isNotEmpty, reason: 'over');

    expect(await service.watchRequests().first, isEmpty);
    expect(closed, ['r_1']);
  });

  test(
    'the question is asked only while connected: a lost connection takes it down, the next greeting brings back what still waits',
    () async {
      final socket = await greeted();
      asked(socket);
      await waitUntil(() => service.watchRequests().first.then((r) => r.isNotEmpty), reason: 'asked');

      await socket.drop();
      await waitUntil(() => service.watchRequests().first.then((r) => r.isEmpty), reason: 'taken down with the connection');

      await waitUntil(() => factory.created.length == 2, reason: 'reconnects');
      final next = factory.latest;
      next.pushGreeting();
      await waitUntil(() => next.commandNamed('session.hello') != null, reason: 'greets again');
      next.replyToHello(cursor: 0);
      asked(next);
      await waitUntil(() => service.watchRequests().first.then((r) => r.isNotEmpty), reason: 'asked again');
    },
  );

  test('Allow goes out as device.approve, and the request is over at once', () async {
    final socket = await greeted();
    asked(socket);
    await waitUntil(() => service.watchRequests().first.then((r) => r.isNotEmpty), reason: 'asked');

    final answered = service.answer(requestId: 'r_1', allow: true);
    await waitUntil(() => socket.commandNamed('device.approve') != null, reason: 'sent');
    expect(socket.commandNamed('device.approve')!['data'], {'request_id': 'r_1', 'allow': true});
    socket.reply(last(socket, 'device.approve'), data: const {});

    expect((await answered).data, isTrue);
    expect(await service.watchRequests().first, isEmpty);
  });

  test('Deny is the same command saying no', () async {
    final socket = await greeted();
    asked(socket);
    await waitUntil(() => service.watchRequests().first.then((r) => r.isNotEmpty), reason: 'asked');

    final answered = service.answer(requestId: 'r_1', allow: false);
    await waitUntil(() => socket.commandNamed('device.approve') != null, reason: 'sent');
    expect(socket.commandNamed('device.approve')!['data'], {'request_id': 'r_1', 'allow': false});
    socket.reply(last(socket, 'device.approve'), data: const {});

    expect((await answered).data, isTrue);
  });

  test('a request that closed meanwhile has nothing left to answer, and goes', () async {
    final socket = await greeted();
    asked(socket);
    await waitUntil(() => service.watchRequests().first.then((r) => r.isNotEmpty), reason: 'asked');

    final answered = service.answer(requestId: 'r_1', allow: true);
    await waitUntil(() => socket.commandNamed('device.approve') != null, reason: 'sent');
    socket.reply(last(socket, 'device.approve'), ok: false, code: 'not_found');

    expect((await answered).data, isFalse);
    expect(await service.watchRequests().first, isEmpty);
  });

  test('an answer that does not get through leaves the question up, to answer again', () async {
    final socket = await greeted();
    asked(socket);
    await waitUntil(() => service.watchRequests().first.then((r) => r.isNotEmpty), reason: 'asked');

    final answered = service.answer(requestId: 'r_1', allow: true);
    await waitUntil(() => socket.commandNamed('device.approve') != null, reason: 'sent');
    socket.reply(last(socket, 'device.approve'), ok: false, code: 'internal');

    expect((await answered).exception, RepositoryException.internal);
    expect(await service.watchRequests().first, hasLength(1));
  });

  test('no answer is queued for a later connection', () async {
    await client.start(url: url, credentialsProvider: () async => const GreetingCredentials());

    final answered = await service.answer(requestId: 'r_1', allow: true);

    expect(answered.exception, RepositoryException.connection);
    expect(factory.latest.commandNamed('device.approve'), isNull);
  });

  test('nothing the request carries reaches the log', () async {
    final lines = <String>[];
    getIt.allowReassignment = true;
    getIt.registerSingleton<LogRepository>(_CapturingLog(lines));
    final socket = await greeted();

    asked(socket, id: 'r_secretrequest', platform: 'Anna\'s ThinkPad');
    await waitUntil(() => service.watchRequests().first.then((r) => r.isNotEmpty), reason: 'asked');

    expect(lines.join('\n'), isNot(contains('ThinkPad')));
    expect(lines.join('\n'), isNot(contains('r_secretrequest')));
  });
}

class _CapturingLog implements LogRepository {
  _CapturingLog(this.lines);

  final List<String> lines;

  @override
  void debug({Object? target, required String message}) => lines.add(message);

  @override
  void error({Object? target, required Object error, StackTrace? stackTrace}) => lines.add(error.toString());
}
