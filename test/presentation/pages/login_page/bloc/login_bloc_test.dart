import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/presentation/pages/login_page/bloc/login_bloc.dart';

import 'login_bloc_test.mocks.dart';

@GenerateMocks([AuthRepository])
void main() {
  provideDummy<RepositoryResult<bool>>(const RepositoryResult.success(data: true));

  group('LoginBloc', () {
    blocTest<LoginBloc, LoginState>(
      'enables submit once the id is non-empty',
      build: () => LoginBloc(demo: true),
      act: (bloc) => bloc.add(const LoginEvent.idChanged('some-id')),
      expect: () => [predicate<LoginState>((s) => s.id == 'some-id' && s.canSubmit && s.status == LoginStatus.idle)],
    );

    blocTest<LoginBloc, LoginState>(
      'toggles canPaste from the clipboard check',
      build: () => LoginBloc(demo: true),
      act: (bloc) => bloc.add(const LoginEvent.clipboardChecked(hasText: true)),
      expect: () => [predicate<LoginState>((s) => s.canPaste)],
    );

    blocTest<LoginBloc, LoginState>(
      'auto outcome with a registered id resolves to navRegistered',
      build: () => LoginBloc(demo: true),
      act: (bloc) => bloc
        ..add(const LoginEvent.idChanged('registered'))
        ..add(const LoginEvent.signInRequested()),
      wait: const Duration(milliseconds: 500),
      expect: () => [
        predicate<LoginState>((s) => s.id == 'registered'),
        predicate<LoginState>((s) => s.status == LoginStatus.loading),
        predicate<LoginState>((s) => s.status == LoginStatus.navRegistered),
      ],
    );

    blocTest<LoginBloc, LoginState>(
      'auto outcome with a new id resolves to navNewId',
      build: () => LoginBloc(demo: true),
      act: (bloc) => bloc
        ..add(const LoginEvent.idChanged('brand-new-id'))
        ..add(const LoginEvent.signInRequested()),
      wait: const Duration(milliseconds: 500),
      expect: () => [
        predicate<LoginState>((s) => s.id == 'brand-new-id'),
        predicate<LoginState>((s) => s.status == LoginStatus.loading),
        predicate<LoginState>((s) => s.status == LoginStatus.navNewId),
      ],
    );

    blocTest<LoginBloc, LoginState>(
      'forced network-error outcome surfaces an inline error',
      build: () => LoginBloc(demo: true),
      act: (bloc) => bloc
        ..add(const LoginEvent.idChanged('x'))
        ..add(const LoginEvent.signInRequested(outcome: LoginOutcome.errorNetwork)),
      wait: const Duration(milliseconds: 500),
      expect: () => [
        predicate<LoginState>((s) => s.id == 'x'),
        predicate<LoginState>((s) => s.status == LoginStatus.loading),
        predicate<LoginState>((s) => s.status == LoginStatus.errorNetwork),
      ],
    );

    blocTest<LoginBloc, LoginState>(
      'ignores sign-in while the id is empty',
      build: () => LoginBloc(demo: true),
      act: (bloc) => bloc.add(const LoginEvent.signInRequested()),
      expect: () => const <LoginState>[],
    );

    blocTest<LoginBloc, LoginState>(
      'navigationHandled resets a terminal status to idle (keeps the id)',
      build: () => LoginBloc(demo: true),
      seed: () => const LoginState(id: 'kept-id', status: LoginStatus.navNewId),
      act: (bloc) => bloc.add(const LoginEvent.navigationHandled()),
      expect: () => [predicate<LoginState>((s) => s.status == LoginStatus.idle && s.id == 'kept-id')],
    );
  });

  // Sign-in stopped being a local decision in feature 031: the button now waits
  // for the server to say who connected, so these cover the real path rather
  // than the demo outcomes above.
  group('LoginBloc real sign-in (demo: false)', () {
    late MockAuthRepository mockAuthRepository;

    setUp(() async {
      await configureDependencies(Environment.test);
      getIt.allowReassignment = true;
      mockAuthRepository = MockAuthRepository();
      getIt.registerSingleton<AuthRepository>(mockAuthRepository);
    });
    tearDown(() async => getIt.reset());

    blocTest<LoginBloc, LoginState>(
      'stays in the waiting state while the server has not answered',
      build: () {
        // Never completes: the point is that the screen shows a wait rather
        // than resolving an outcome it has not been told.
        when(mockAuthRepository.signIn(identifier: anyNamed('identifier'))).thenAnswer((_) => Completer<RepositoryResult<bool>>().future);
        return LoginBloc();
      },
      act: (bloc) => bloc
        ..add(const LoginEvent.idChanged('some-id'))
        ..add(const LoginEvent.signInRequested()),
      wait: const Duration(milliseconds: 300),
      expect: () => [predicate<LoginState>((s) => s.id == 'some-id'), predicate<LoginState>((s) => s.status == LoginStatus.loading)],
    );

    blocTest<LoginBloc, LoginState>(
      'a link that will not parse says so, and not "check your connection"',
      build: () {
        when(
          mockAuthRepository.signIn(identifier: anyNamed('identifier')),
        ).thenAnswer((_) async => const RepositoryResult.error(exception: RepositoryException.invalidRequest));
        return LoginBloc();
      },
      act: (bloc) => bloc
        ..add(const LoginEvent.idChanged('not a link'))
        ..add(const LoginEvent.signInRequested()),
      wait: const Duration(milliseconds: 300),
      expect: () => [
        predicate<LoginState>((s) => s.id == 'not a link'),
        predicate<LoginState>((s) => s.status == LoginStatus.loading),
        predicate<LoginState>((s) => s.status == LoginStatus.errorFormat),
      ],
    );

    blocTest<LoginBloc, LoginState>(
      'an expired link is told apart from a rejected one, because the fix differs',
      build: () {
        when(
          mockAuthRepository.signIn(identifier: anyNamed('identifier')),
        ).thenAnswer((_) async => const RepositoryResult.error(exception: RepositoryException.notFound));
        return LoginBloc();
      },
      act: (bloc) => bloc
        ..add(const LoginEvent.idChanged('some-link'))
        ..add(const LoginEvent.signInRequested()),
      wait: const Duration(milliseconds: 300),
      expect: () => [
        predicate<LoginState>((s) => s.id == 'some-link'),
        predicate<LoginState>((s) => s.status == LoginStatus.loading),
        predicate<LoginState>((s) => s.status == LoginStatus.errorExpired),
      ],
    );

    blocTest<LoginBloc, LoginState>(
      'a rejected link says the link is unusable',
      build: () {
        when(
          mockAuthRepository.signIn(identifier: anyNamed('identifier')),
        ).thenAnswer((_) async => const RepositoryResult.error(exception: RepositoryException.authentication));
        return LoginBloc();
      },
      act: (bloc) => bloc
        ..add(const LoginEvent.idChanged('some-link'))
        ..add(const LoginEvent.signInRequested()),
      wait: const Duration(milliseconds: 300),
      expect: () => [
        predicate<LoginState>((s) => s.id == 'some-link'),
        predicate<LoginState>((s) => s.status == LoginStatus.loading),
        predicate<LoginState>((s) => s.status == LoginStatus.errorRejected),
      ],
    );

    blocTest<LoginBloc, LoginState>(
      'a failed handshake shows a retryable error and guesses no outcome',
      build: () {
        when(
          mockAuthRepository.signIn(identifier: anyNamed('identifier')),
        ).thenAnswer((_) async => const RepositoryResult.error(exception: RepositoryException.connection));
        return LoginBloc();
      },
      act: (bloc) => bloc
        ..add(const LoginEvent.idChanged('some-id'))
        ..add(const LoginEvent.signInRequested()),
      wait: const Duration(milliseconds: 300),
      expect: () => [
        predicate<LoginState>((s) => s.id == 'some-id'),
        predicate<LoginState>((s) => s.status == LoginStatus.loading),
        // Not navNewId: an unanswered sign-in used to be resolved locally, and
        // guessing "new" here is exactly what steals a returning person's name.
        predicate<LoginState>((s) => s.status == LoginStatus.errorNetwork && s.canSubmit),
      ],
    );

    blocTest<LoginBloc, LoginState>(
      'the error is retryable - a second press really re-runs sign-in',
      build: () {
        when(
          mockAuthRepository.signIn(identifier: anyNamed('identifier')),
        ).thenAnswer((_) async => const RepositoryResult.error(exception: RepositoryException.connection));
        return LoginBloc();
      },
      act: (bloc) async {
        bloc.add(const LoginEvent.idChanged('some-id'));
        bloc.add(const LoginEvent.signInRequested());
        await Future<void>.delayed(const Duration(milliseconds: 100));
        bloc.add(const LoginEvent.signInRequested());
      },
      wait: const Duration(milliseconds: 300),
      verify: (_) => verify(mockAuthRepository.signIn(identifier: 'some-id')).called(2),
    );

    blocTest<LoginBloc, LoginState>(
      'a successful sign-in navigates nowhere from here - the app-state spine does',
      build: () {
        when(
          mockAuthRepository.signIn(identifier: anyNamed('identifier')),
        ).thenAnswer((_) async => const RepositoryResult.success(data: true));
        return LoginBloc();
      },
      act: (bloc) => bloc
        ..add(const LoginEvent.idChanged('some-id'))
        ..add(const LoginEvent.signInRequested()),
      wait: const Duration(milliseconds: 300),
      expect: () => [
        predicate<LoginState>((s) => s.id == 'some-id'),
        predicate<LoginState>((s) => s.status == LoginStatus.loading),
        predicate<LoginState>((s) => s.status == LoginStatus.idle),
      ],
    );
  });
}
