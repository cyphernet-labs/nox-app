import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/presentation/pages/login_page/bloc/login_bloc.dart';

import 'login_bloc_test.mocks.dart';

/// A link with one direct address and nothing else (the contract's `minimal`
/// vector).
const String _homeLink = 'nox://pair/A6CapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODwEGwKgBFCD7';

/// A link that also carries the server's onion address (the `full` vector).
const String _onionLink =
    'nox://pair/A6CapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODwEGwKgBFCD7AxFub3guZXhhbXBsZS5vcmcg-wQgF8t5-ytBIPKx7GXkGY1uCLKOgT_rAeSkAIObheGAgM4';

/// A link of version 4 - newer than this build.
const String _newerLink = 'nox://pair/BKCapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODw';

@GenerateMocks([AuthRepository])
void main() {
  provideDummy<RepositoryResult<bool>>(const RepositoryResult.success(data: true));

  group('LoginBloc (demo)', () {
    setUp(() async {
      await configureDependencies(Environment.test);
      getIt.allowReassignment = true;
    });
    tearDown(() async => getIt.reset());

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

  // Since phase 045 this screen only READS the link: a readable one goes on to
  // the connection screen, which shows where it leads and pairs. Nothing here
  // signs in, so nothing here can be told about a server.
  group('LoginBloc real flow (demo: false)', () {
    late MockAuthRepository auth;

    setUp(() async {
      await configureDependencies(Environment.test);
      getIt.allowReassignment = true;
      auth = MockAuthRepository();
      getIt.registerSingleton<AuthRepository>(auth);
    });
    tearDown(() async => getIt.reset());

    for (final (kind, link) in [('a link with a direct address only', _homeLink), ('a link carrying the onion address', _onionLink)]) {
      blocTest<LoginBloc, LoginState>(
        '$kind goes on to the connection screen, and nothing is signed in from here',
        build: LoginBloc.new,
        act: (bloc) => bloc
          ..add(LoginEvent.idChanged(link))
          ..add(const LoginEvent.signInRequested()),
        expect: () => [predicate<LoginState>((s) => s.id == link), predicate<LoginState>((s) => s.status == LoginStatus.navConnect)],
        verify: (_) => verifyNever(auth.signIn(identifier: anyNamed('identifier'), connection: anyNamed('connection'))),
      );
    }

    blocTest<LoginBloc, LoginState>(
      'surrounding whitespace is no reason to refuse a pasted link',
      build: LoginBloc.new,
      act: (bloc) => bloc
        ..add(const LoginEvent.idChanged('  $_homeLink\n'))
        ..add(const LoginEvent.signInRequested()),
      verify: (bloc) => expect(bloc.state.status, LoginStatus.navConnect),
    );

    blocTest<LoginBloc, LoginState>(
      'a link that will not parse says so here - scan it again - and goes nowhere',
      build: LoginBloc.new,
      act: (bloc) => bloc
        ..add(const LoginEvent.idChanged('not a link'))
        ..add(const LoginEvent.signInRequested()),
      expect: () => [predicate<LoginState>((s) => s.id == 'not a link'), predicate<LoginState>((s) => s.status == LoginStatus.errorFormat)],
    );

    blocTest<LoginBloc, LoginState>(
      'a link newer than this build says to update the app (044, FR-017), and goes nowhere',
      build: LoginBloc.new,
      act: (bloc) => bloc
        ..add(const LoginEvent.idChanged(_newerLink))
        ..add(const LoginEvent.signInRequested()),
      expect: () => [
        predicate<LoginState>((s) => s.id == _newerLink),
        predicate<LoginState>((s) => s.status == LoginStatus.errorNewerVersion),
      ],
    );

    blocTest<LoginBloc, LoginState>(
      'typing clears a refusal, because the next link may well be the right one',
      build: LoginBloc.new,
      seed: () => const LoginState(id: 'not a link', status: LoginStatus.errorFormat),
      act: (bloc) => bloc.add(const LoginEvent.idChanged(_homeLink)),
      expect: () => [predicate<LoginState>((s) => s.status == LoginStatus.idle && s.id == _homeLink)],
    );

    blocTest<LoginBloc, LoginState>(
      'back from the connection screen the link is still there, and Sign in takes it there again',
      build: LoginBloc.new,
      seed: () => const LoginState(id: _homeLink, status: LoginStatus.navConnect),
      act: (bloc) => bloc
        ..add(const LoginEvent.navigationHandled())
        ..add(const LoginEvent.signInRequested()),
      expect: () => [
        predicate<LoginState>((s) => s.status == LoginStatus.idle && s.id == _homeLink),
        predicate<LoginState>((s) => s.status == LoginStatus.navConnect),
      ],
    );
  });
}
