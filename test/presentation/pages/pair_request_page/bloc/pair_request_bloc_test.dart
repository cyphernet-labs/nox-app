import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/remote/socket/server_frame.dart';
import 'package:nox_app/data/sync/pair_request_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/person/person_repository.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:nox_app/presentation/pages/pair_request_page/bloc/pair_request_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../data/remote/socket/fake_socket.dart';
import 'pair_request_bloc_test.mocks.dart';

@GenerateMocks([PersonRepository])
void main() {
  group('PairRequestBloc', () {
    final url = Uri.parse('ws://localhost:1/ws');
    late FakeSocketFactory factory;
    late NoxSocketClient client;
    late PairRequestService service;
    late MockPersonRepository repository;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      await configureDependencies(Environment.test);
      await getIt<AppDatabase>().clearEntireDatabase();
      provideDummy<RepositoryResult<bool>>(const RepositoryResult<bool>.success(data: true));

      factory = FakeSocketFactory();
      client = NoxSocketClient(factory, getIt<SyncRepository>());
      service = PairRequestService(client);
      repository = MockPersonRepository();
      getIt.allowReassignment = true;
      getIt.registerSingleton<PairRequestService>(service);
      getIt.registerSingleton<PersonRepository>(repository);
    });

    tearDown(() async {
      await client.stop();
      await getIt.reset();
    });

    Future<FakeSocket> connect() async {
      await client.start(url: url, credentialsProvider: () async => const GreetingCredentials.unpaired());
      final socket = factory.latest;
      socket.pushGreeting();
      return socket;
    }

    int seconds(Duration fromNow) => (DateTime.now().add(fromNow).millisecondsSinceEpoch / 1000).floor();

    Future<void> pushQuestion(FakeSocket socket, String id) async {
      socket.pushEvent(
        seq: 0,
        event: ServerEvent.personPairRequested,
        data: {'request_id': id, 'invited_at': seconds(-const Duration(minutes: 1)), 'expires_at': seconds(const Duration(minutes: 5))},
      );
      for (var i = 0; i < 100 && service.current.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    blocTest<PairRequestBloc, PairRequestState>(
      'settles when ANOTHER device of the owner answers, so the surface is not a dead end',
      // Without this the second device keeps a modal with no barrier dismiss and
      // no back arrow, whose only two buttons now answer a settled request and
      // are refused. There is no way out of the app but to kill it.
      setUp: () async {
        final socket = await connect();
        await pushQuestion(socket, 'r_1');
        socket.pushEvent(seq: 0, event: ServerEvent.personPairResolved, data: {'request_id': 'r_1', 'outcome': 'approved'});
      },
      build: () => PairRequestBloc(requestId: 'r_1'),
      wait: const Duration(milliseconds: 200),
      expect: () => [predicate<PairRequestState>((s) => s.settled && !s.failed)],
    );

    blocTest<PairRequestBloc, PairRequestState>(
      'an answer to a question that is already gone settles rather than offering a retry',
      setUp: () async {
        final socket = await connect();
        await pushQuestion(socket, 'r_2');
      },
      build: () {
        when(
          repository.confirm(requestId: anyNamed('requestId'), approve: anyNamed('approve')),
        ).thenAnswer((_) async => const RepositoryResult<bool>.error(exception: RepositoryException.notFound));
        return PairRequestBloc(requestId: 'r_2');
      },
      act: (bloc) => bloc.add(const PairRequestEvent.answered(approve: true)),
      wait: const Duration(milliseconds: 100),
      expect: () => [
        predicate<PairRequestState>((s) => s.sending),
        // Nothing left to decide: somebody answered it or it ran out of time,
        // and offering the buttons again would offer the same refusal again.
        predicate<PairRequestState>((s) => s.settled && !s.failed && !s.sending),
      ],
    );

    blocTest<PairRequestBloc, PairRequestState>(
      'a real failure keeps the question answerable',
      setUp: () async {
        final socket = await connect();
        await pushQuestion(socket, 'r_3');
      },
      build: () {
        when(
          repository.confirm(requestId: anyNamed('requestId'), approve: anyNamed('approve')),
        ).thenAnswer((_) async => const RepositoryResult<bool>.error(exception: RepositoryException.connection));
        return PairRequestBloc(requestId: 'r_3');
      },
      act: (bloc) => bloc.add(const PairRequestEvent.answered(approve: false)),
      wait: const Duration(milliseconds: 100),
      expect: () => [
        predicate<PairRequestState>((s) => s.sending),
        predicate<PairRequestState>((s) => s.failed && !s.settled && !s.sending),
      ],
    );

    blocTest<PairRequestBloc, PairRequestState>(
      'the surface closes only on the SERVER answer, never on the tap',
      setUp: () async {
        final socket = await connect();
        await pushQuestion(socket, 'r_4');
      },
      build: () {
        when(
          repository.confirm(requestId: anyNamed('requestId'), approve: anyNamed('approve')),
        ).thenAnswer((_) async => const RepositoryResult<bool>.success(data: true));
        return PairRequestBloc(requestId: 'r_4');
      },
      act: (bloc) => bloc.add(const PairRequestEvent.answered(approve: true)),
      wait: const Duration(milliseconds: 100),
      expect: () => [
        // Closing on the tap would leave the owner believing they decided
        // something the server never heard.
        predicate<PairRequestState>((s) => s.sending && !s.settled),
        predicate<PairRequestState>((s) => s.settled && !s.sending),
      ],
    );
  });
}
