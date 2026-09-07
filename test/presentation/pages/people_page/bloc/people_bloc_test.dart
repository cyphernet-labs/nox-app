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
import 'package:nox_app/domain/model/person/person_model.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/person/person_repository.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:nox_app/presentation/pages/people_page/bloc/people_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../data/remote/socket/fake_socket.dart';
import 'people_bloc_test.mocks.dart';

@GenerateMocks([PersonRepository])
void main() {
  group('PeopleBloc', () {
    final url = Uri.parse('ws://localhost:1/ws');
    late MockPersonRepository repository;
    late FakeSocketFactory factory;
    late NoxSocketClient client;
    late PairRequestService service;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      await configureDependencies(Environment.test);
      await getIt<AppDatabase>().clearEntireDatabase();
      factory = FakeSocketFactory();
      client = NoxSocketClient(factory, getIt<SyncRepository>());
      service = PairRequestService(client);
      provideDummy<RepositoryResult<String>>(const RepositoryResult<String>.success(data: ''));
      provideDummy<RepositoryResult<List<PersonModel>>>(const RepositoryResult<List<PersonModel>>.success(data: []));
      repository = MockPersonRepository();
      getIt.allowReassignment = true;
      getIt.registerSingleton<PersonRepository>(repository);
    });

    tearDown(() async {
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

    blocTest<PeopleBloc, PeopleState>(
      'a second tap while an invite is in flight mints nothing',
      // Every call creates a 24-hour token that admits a NEW person and cannot
      // be revoked. Three impatient taps would leave two live invites that
      // nothing on this screen ever shows again.
      build: () {
        when(repository.invitePerson()).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 80));
          return const RepositoryResult<String>.success(data: 'https://nox.app/p/#AQEK');
        });
        return PeopleBloc();
      },
      act: (bloc) => bloc
        ..add(const PeopleEvent.inviteRequested())
        ..add(const PeopleEvent.inviteRequested())
        ..add(const PeopleEvent.inviteRequested()),
      wait: const Duration(milliseconds: 200),
      verify: (_) => verify(repository.invitePerson()).called(1),
      expect: () => [
        predicate<PeopleState>((s) => s.inviting),
        predicate<PeopleState>((s) => !s.inviting && s.inviteLink == 'https://nox.app/p/#AQEK'),
      ],
    );

    blocTest<PeopleBloc, PeopleState>(
      '"only the owner may invite" is not "couldn\'t create an invite"',
      // One says the app should not have offered this at all; the other says
      // try again. Telling them apart is the whole reason the wire keeps a
      // separate code for it.
      build: () {
        when(
          repository.invitePerson(),
        ).thenAnswer((_) async => const RepositoryResult<String>.error(exception: RepositoryException.notOwner));
        return PeopleBloc();
      },
      act: (bloc) => bloc.add(const PeopleEvent.inviteRequested()),
      wait: const Duration(milliseconds: 100),
      expect: () => [
        predicate<PeopleState>((s) => s.inviting),
        predicate<PeopleState>((s) => s.notOwner && !s.inviteFailed && !s.inviting),
      ],
    );

    blocTest<PeopleBloc, PeopleState>(
      'an ordinary failure invites a retry',
      build: () {
        when(
          repository.invitePerson(),
        ).thenAnswer((_) async => const RepositoryResult<String>.error(exception: RepositoryException.connection));
        return PeopleBloc();
      },
      act: (bloc) => bloc.add(const PeopleEvent.inviteRequested()),
      wait: const Duration(milliseconds: 100),
      expect: () => [
        predicate<PeopleState>((s) => s.inviting),
        predicate<PeopleState>((s) => s.inviteFailed && !s.notOwner && !s.inviting),
      ],
    );

    blocTest<PeopleBloc, PeopleState>(
      'a question answered elsewhere re-reads the circle and leaves the invite alone',
      // The surface that takes the decision opens OVER this screen and pops back
      // to it, so nothing else would ask again — the person just let in would
      // stay invisible until the screen was left and re-entered.
      //
      // The link is deliberately untouched: a resolved question says which
      // REQUEST was answered, never which invite it spent, and each
      // person.invite mints its own token. Clearing on any outcome would
      // discard one the owner minted and has not sent yet — unrevocable and
      // unlisted (Q17), so gone for good.
      setUp: () async {
        getIt.registerSingleton<PairRequestService>(service);
        final socket = await connect();
        socket.pushEvent(
          seq: 0,
          event: ServerEvent.personPairRequested,
          data: {
            'request_id': 'r_1',
            'invited_at': seconds(-const Duration(minutes: 1)),
            'expires_at': seconds(const Duration(minutes: 5)),
          },
        );
        for (var i = 0; i < 100 && service.current.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      },
      build: () {
        when(repository.invitePerson()).thenAnswer((_) async => const RepositoryResult<String>.success(data: 'https://nox.app/p/#AQEK'));
        when(repository.getPeople()).thenAnswer(
          (_) async => const RepositoryResult<List<PersonModel>>.success(
            data: [
              PersonModel(id: 'u_owner', label: 'Anna', isOwner: true, isSelf: true),
              PersonModel(id: 'u_guest', label: 'Boris', isOwner: false, isSelf: false),
            ],
          ),
        );
        return PeopleBloc();
      },
      act: (bloc) async {
        bloc.add(const PeopleEvent.inviteRequested());
        // Settled before the outcome is pushed: the two are separate concerns,
        // and overlapping them would test the bloc's event concurrency instead.
        for (var i = 0; i < 100 && bloc.state.inviteLink == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(bloc.state.inviteLink, isNotNull, reason: 'the invite landed before the question resolved');
        factory.latest.pushEvent(seq: 0, event: ServerEvent.personPairResolved, data: {'request_id': 'r_1', 'outcome': 'approved'});
      },
      wait: const Duration(milliseconds: 150),
      verify: (bloc) {
        expect(bloc.state.people, hasLength(2), reason: 'the person just let in is visible without leaving the screen');
        expect(bloc.state.inviteLink, 'https://nox.app/p/#AQEK', reason: 'a live invite is not discarded on somebody else\'s outcome');
      },
    );

    blocTest<PeopleBloc, PeopleState>(
      'the circle is read from the server, never from a cache',
      build: () {
        when(repository.getPeople()).thenAnswer(
          (_) async => const RepositoryResult<List<PersonModel>>.success(
            data: [
              PersonModel(id: 'u_owner', label: 'Anna', isOwner: true, isSelf: true),
              PersonModel(id: 'u_guest', label: 'Boris', isOwner: false, isSelf: false),
            ],
          ),
        );
        return PeopleBloc();
      },
      act: (bloc) => bloc.add(const PeopleEvent.initialize()),
      wait: const Duration(milliseconds: 100),
      expect: () => [
        predicate<PeopleState>((s) => s.loading),
        predicate<PeopleState>((s) => !s.loading && s.people.length == 2 && s.self?.label == 'Anna' && s.others.single.label == 'Boris'),
      ],
    );
  });
}
