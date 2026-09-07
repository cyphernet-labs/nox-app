import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/person/person_model.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/person/person_repository.dart';
import 'package:nox_app/presentation/pages/people_page/bloc/people_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'people_bloc_test.mocks.dart';

@GenerateMocks([PersonRepository])
void main() {
  group('PeopleBloc', () {
    late MockPersonRepository repository;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      await configureDependencies(Environment.test);
      provideDummy<RepositoryResult<String>>(const RepositoryResult<String>.success(data: ''));
      provideDummy<RepositoryResult<List<PersonModel>>>(const RepositoryResult<List<PersonModel>>.success(data: []));
      repository = MockPersonRepository();
      getIt.allowReassignment = true;
      getIt.registerSingleton<PersonRepository>(repository);
    });

    tearDown(getIt.reset);

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
