import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/remote/socket/server_frame.dart';
import 'package:nox_app/data/sync/pair_request_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../remote/socket/fake_socket.dart';

void main() {
  group('PairRequestService', () {
    final url = Uri.parse('ws://localhost:1/ws');
    late FakeSocketFactory factory;
    late NoxSocketClient client;
    late PairRequestService service;

    Future<void> waitUntil(bool Function() done, {String reason = ''}) async {
      for (var i = 0; i < 400; i++) {
        if (done()) return;
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
      client = NoxSocketClient(factory, getIt<SyncRepository>());
      service = PairRequestService(client);
    });

    tearDown(() async {
      await service.dispose();
      await client.stop();
      await getIt.reset();
    });

    /// Brings a connection up and returns the socket to push frames on.
    Future<FakeSocket> connect() async {
      await client.start(url: url, credentialsProvider: () async => const GreetingCredentials.unpaired());
      final socket = factory.latest;
      socket.pushGreeting();
      return socket;
    }

    int seconds(Duration fromNow) => (DateTime.now().add(fromNow).millisecondsSinceEpoch / 1000).floor();

    test('a question arrives and leaves when the server says it is resolved', () async {
      final socket = await connect();
      socket.pushEvent(
        seq: 0,
        event: ServerEvent.personPairRequested,
        data: {'request_id': 'r_1', 'invited_at': seconds(-const Duration(minutes: 1)), 'expires_at': seconds(const Duration(minutes: 5))},
      );
      await waitUntil(() => service.current.length == 1, reason: 'the question arrived');
      expect(service.current.single.requestId, 'r_1');

      socket.pushEvent(seq: 0, event: ServerEvent.personPairResolved, data: {'request_id': 'r_1', 'outcome': 'approved'});
      await waitUntil(() => service.current.isEmpty, reason: 'the question left');
    });

    test('the same question re-sent on a greeting replaces rather than duplicates', () async {
      // The server re-sends every waiting request after each greeting, so the
      // second copy is the normal case rather than an anomaly.
      final socket = await connect();
      final frame = {
        'request_id': 'r_1',
        'invited_at': seconds(-const Duration(minutes: 1)),
        'expires_at': seconds(const Duration(minutes: 5)),
      };
      socket.pushEvent(seq: 0, event: ServerEvent.personPairRequested, data: frame);
      socket.pushEvent(seq: 0, event: ServerEvent.personPairRequested, data: frame);
      await waitUntil(() => service.current.isNotEmpty, reason: 'the question arrived');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(service.current, hasLength(1));
    });

    test('two questions are kept apart and ordered oldest first', () async {
      final socket = await connect();
      socket.pushEvent(
        seq: 0,
        event: ServerEvent.personPairRequested,
        data: {
          'request_id': 'r_new',
          'invited_at': seconds(-const Duration(minutes: 1)),
          'expires_at': seconds(const Duration(minutes: 5)),
        },
      );
      socket.pushEvent(
        seq: 0,
        event: ServerEvent.personPairRequested,
        data: {
          'request_id': 'r_old',
          'invited_at': seconds(-const Duration(minutes: 9)),
          'expires_at': seconds(const Duration(minutes: 4)),
        },
      );
      await waitUntil(() => service.current.length == 2, reason: 'both questions arrived');

      expect(service.current.map((r) => r.requestId), ['r_old', 'r_new'], reason: 'two people knocking is two decisions');
    });

    test('a question already past its deadline is not shown', () async {
      final socket = await connect();
      socket.pushEvent(
        seq: 0,
        event: ServerEvent.personPairRequested,
        data: {'request_id': 'r_1', 'invited_at': seconds(-const Duration(minutes: 9)), 'expires_at': seconds(-const Duration(minutes: 1))},
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(service.current, isEmpty, reason: 'answering it could not work');
    });

    test('a question whose deadline the server did not state is KEPT', () async {
      // Dropping it would swallow the question over a missing field or a device
      // clock that runs fast, and the person at the door would wait out the
      // whole window for nothing. The server remains the authority on when a
      // question dies.
      final socket = await connect();
      socket.pushEvent(
        seq: 0,
        event: ServerEvent.personPairRequested,
        data: {'request_id': 'r_1', 'invited_at': seconds(-const Duration(minutes: 1))},
      );
      await waitUntil(() => service.current.length == 1, reason: 'the question survived');
      expect(service.current.single.expiresAt, isNull);

      socket.pushEvent(seq: 0, event: ServerEvent.personPairResolved, data: {'request_id': 'r_1', 'outcome': 'expired'});
      await waitUntil(() => service.current.isEmpty, reason: 'and the server closed it');
    });
  });
}
