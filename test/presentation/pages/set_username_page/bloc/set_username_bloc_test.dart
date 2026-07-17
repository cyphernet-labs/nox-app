import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/presentation/pages/set_username_page/bloc/set_username_bloc.dart';

import 'set_username_bloc_test.mocks.dart';

@GenerateMocks([AuthRepository])
void main() {
  provideDummy<RepositoryResult<bool>>(const RepositoryResult.success(data: true));

  group('SetUsernameBloc', () {
    blocTest<SetUsernameBloc, SetUsernameState>(
      'rejects an invalid charset immediately, without a server check',
      build: () => SetUsernameBloc(demo: true),
      act: (bloc) => bloc.add(const SetUsernameEvent.nameChanged('bad name!')),
      expect: () => [predicate<SetUsernameState>((s) => s.status == UsernameStatus.invalidCharset)],
    );

    blocTest<SetUsernameBloc, SetUsernameState>(
      'empty name disables submit',
      build: () => SetUsernameBloc(demo: true),
      act: (bloc) => bloc.add(const SetUsernameEvent.nameChanged('')),
      expect: () => [predicate<SetUsernameState>((s) => s.status == UsernameStatus.empty && !s.canSubmit)],
    );

    blocTest<SetUsernameBloc, SetUsernameState>(
      'a free valid name resolves to valid after the debounced check',
      build: () => SetUsernameBloc(demo: true),
      act: (bloc) => bloc.add(const SetUsernameEvent.nameChanged('Freename')),
      wait: const Duration(milliseconds: 700),
      expect: () => [
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.checking),
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.valid && s.canSubmit),
      ],
    );

    blocTest<SetUsernameBloc, SetUsernameState>(
      'a taken name resolves to taken',
      build: () => SetUsernameBloc(demo: true),
      act: (bloc) => bloc.add(const SetUsernameEvent.nameChanged('NOX')),
      wait: const Duration(milliseconds: 700),
      expect: () => [
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.checking),
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.taken),
      ],
    );

    blocTest<SetUsernameBloc, SetUsernameState>(
      'uniqueness is case-sensitive: "nox" is free even though "NOX" is taken',
      build: () => SetUsernameBloc(demo: true),
      act: (bloc) => bloc.add(const SetUsernameEvent.nameChanged('nox')),
      wait: const Duration(milliseconds: 700),
      expect: () => [
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.checking),
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.valid),
      ],
    );

    blocTest<SetUsernameBloc, SetUsernameState>(
      'Done with the success outcome navigates',
      build: () => SetUsernameBloc(demo: true),
      act: (bloc) => bloc.add(const SetUsernameEvent.doneRequested()),
      wait: const Duration(milliseconds: 500),
      expect: () => [
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.submitting),
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.navSuccess),
      ],
    );

    blocTest<SetUsernameBloc, SetUsernameState>(
      'Done with the race-taken outcome shows an inline error',
      build: () => SetUsernameBloc(demo: true),
      act: (bloc) => bloc.add(const SetUsernameEvent.doneRequested(outcome: UsernameOutcome.raceTaken)),
      wait: const Duration(milliseconds: 500),
      expect: () => [
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.submitting),
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.raceTaken),
      ],
    );

    blocTest<SetUsernameBloc, SetUsernameState>(
      'Done with the fatal outcome maps to a nav-fatal error (demo)',
      build: () => SetUsernameBloc(demo: true),
      act: (bloc) => bloc.add(const SetUsernameEvent.doneRequested(outcome: UsernameOutcome.fatal)),
      wait: const Duration(milliseconds: 500),
      expect: () => [
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.submitting),
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.navFatal),
      ],
    );

    blocTest<SetUsernameBloc, SetUsernameState>(
      'navigationHandled resets a terminal status to valid',
      build: () => SetUsernameBloc(demo: true),
      seed: () => const SetUsernameState(name: 'Anna', status: UsernameStatus.navSuccess),
      act: (bloc) => bloc.add(const SetUsernameEvent.navigationHandled()),
      expect: () => [predicate<SetUsernameState>((s) => s.status == UsernameStatus.valid)],
    );
  });

  group('SetUsernameBloc production onboarding-completion (demo: false)', () {
    late MockAuthRepository mockAuthRepository;

    setUp(() async {
      await configureDependencies(Environment.test);
      getIt.allowReassignment = true;
      mockAuthRepository = MockAuthRepository();
      getIt.registerSingleton<AuthRepository>(mockAuthRepository);
    });
    tearDown(() async => getIt.reset());

    blocTest<SetUsernameBloc, SetUsernameState>(
      'Done marks onboarding complete with the chosen label and maps success to valid',
      build: () {
        when(
          mockAuthRepository.completeOnboarding(label: anyNamed('label')),
        ).thenAnswer((_) async => const RepositoryResult.success(data: true));
        return SetUsernameBloc(initialName: 'Alice');
      },
      act: (bloc) => bloc.add(const SetUsernameEvent.doneRequested()),
      wait: const Duration(milliseconds: 200),
      expect: () => [
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.submitting),
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.valid),
      ],
      verify: (_) => verify(mockAuthRepository.completeOnboarding(label: 'Alice')).called(1),
    );

    blocTest<SetUsernameBloc, SetUsernameState>(
      'Done maps a completeOnboarding error to nav-fatal',
      build: () {
        when(
          mockAuthRepository.completeOnboarding(label: anyNamed('label')),
        ).thenAnswer((_) async => const RepositoryResult.error(exception: RepositoryException.unknown));
        return SetUsernameBloc(initialName: 'Alice');
      },
      act: (bloc) => bloc.add(const SetUsernameEvent.doneRequested()),
      wait: const Duration(milliseconds: 200),
      expect: () => [
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.submitting),
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.navFatal),
      ],
    );

    blocTest<SetUsernameBloc, SetUsernameState>(
      'Skip marks onboarding complete without a label and maps success to valid',
      build: () {
        when(
          mockAuthRepository.completeOnboarding(label: anyNamed('label')),
        ).thenAnswer((_) async => const RepositoryResult.success(data: true));
        return SetUsernameBloc();
      },
      act: (bloc) => bloc.add(const SetUsernameEvent.skipRequested()),
      wait: const Duration(milliseconds: 200),
      expect: () => [
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.submitting),
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.valid),
      ],
      verify: (_) => verify(mockAuthRepository.completeOnboarding()).called(1),
    );

    blocTest<SetUsernameBloc, SetUsernameState>(
      'Skip maps a completeOnboarding error to nav-fatal',
      build: () {
        when(
          mockAuthRepository.completeOnboarding(label: anyNamed('label')),
        ).thenAnswer((_) async => const RepositoryResult.error(exception: RepositoryException.unknown));
        return SetUsernameBloc();
      },
      act: (bloc) => bloc.add(const SetUsernameEvent.skipRequested()),
      wait: const Duration(milliseconds: 200),
      expect: () => [
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.submitting),
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.navFatal),
      ],
    );

    blocTest<SetUsernameBloc, SetUsernameState>(
      'Skip is ignored while already submitting (re-entry guard)',
      build: () {
        when(
          mockAuthRepository.completeOnboarding(label: anyNamed('label')),
        ).thenAnswer((_) async => const RepositoryResult.success(data: true));
        return SetUsernameBloc();
      },
      seed: () => const SetUsernameState(name: 'Alice', status: UsernameStatus.submitting),
      act: (bloc) => bloc.add(const SetUsernameEvent.skipRequested()),
      wait: const Duration(milliseconds: 200),
      expect: () => <SetUsernameState>[],
      verify: (_) => verifyNever(mockAuthRepository.completeOnboarding(label: anyNamed('label'))),
    );
  });
}
