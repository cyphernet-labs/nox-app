import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/presentation/pages/login_page/bloc/login_bloc.dart';

import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';

import 'login_bloc_test.mocks.dart';

/// A link with one direct address and nothing else (the contract's `minimal`
/// vector).
const String _homeLink = 'nox://pair/A6CapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODwEGwKgBFCD7';

/// A link that also carries the server's onion address (the `full` vector).
/// Until phase 045 it pairs only at home all the same: the onion service opens
/// for a paired device's key alone.
const String _onionLink =
    'nox://pair/A6CapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODwEGwKgBFCD7AxFub3guZXhhbXBsZS5vcmcg-wQgF8t5-ytBIPKx7GXkGY1uCLKOgT_rAeSkAIObheGAgM4';

/// A phase this test drives by hand. The real one is the socket's.
class _FakePhase implements SessionPhaseService {
  final StreamController<SessionPhase> _controller = StreamController<SessionPhase>.broadcast();
  SessionPhase _phase = SessionPhase.disconnected;

  void emit(SessionPhase next) {
    _phase = next;
    _controller.add(next);
  }

  @override
  SessionPhase get phase => _phase;

  @override
  Stream<SessionPhase> watchPhase() => _controller.stream;

  @override
  Future<void> reconnect() async {}
}

@GenerateMocks([AuthRepository])
void main() {
  provideDummy<RepositoryResult<bool>>(const RepositoryResult.success(data: true));

  group('LoginBloc', () {
    // The bloc watches the session phase since feature 036 - the pin is checked
    // during the handshake, so a refusal never reaches the sign-in result - and
    // that service comes from the container.
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

  group('LoginBloc and the server that is not the one the link named', () {
    late _FakePhase phase;

    setUp(() async {
      await configureDependencies(Environment.test);
      getIt.allowReassignment = true;
      phase = _FakePhase();
      getIt.registerSingleton<SessionPhaseService>(phase);
    });
    tearDown(() async => getIt.reset());

    blocTest<LoginBloc, LoginState>(
      'a refusal with nothing usable in the field is its own error, not a network one',
      // Telling the person to check their connection here sends them after
      // something that is working perfectly and will never be the cause.
      build: () => LoginBloc(demo: true),
      seed: () => const LoginState(id: 'not a link'),
      act: (bloc) async {
        await Future<void>.delayed(Duration.zero);
        phase.emit(SessionPhase.serverMismatch);
      },
      expect: () => [predicate<LoginState>((s) => s.status == LoginStatus.errorServerMismatch)],
    );

    blocTest<LoginBloc, LoginState>(
      'until phase 045 even a link carrying the onion address pairs at home: a stranger there means "not home"',
      // The pairing goes over the link's direct addresses only (FR-019), so a
      // stranger's key can only have met it there - where it is the expected
      // answer away from home.
      build: () => LoginBloc(demo: true),
      seed: () => const LoginState(id: _onionLink),
      act: (bloc) async {
        await Future<void>.delayed(Duration.zero);
        phase.emit(SessionPhase.serverMismatch);
      },
      expect: () => [predicate<LoginState>((s) => s.status == LoginStatus.errorHomeNetworkOnly)],
    );

    blocTest<LoginBloc, LoginState>(
      'a stranger at the address of a link means "not home", not "wrong server" (FR-011)',
      // Away from home a different machine sits at that address, and the link
      // has no other road. "This server doesn't match its link" would send the
      // person looking for a rebuilt server that is sitting at home untouched.
      build: () => LoginBloc(demo: true),
      seed: () => const LoginState(id: _homeLink),
      act: (bloc) async {
        await Future<void>.delayed(Duration.zero);
        phase.emit(SessionPhase.serverMismatch);
      },
      expect: () => [predicate<LoginState>((s) => s.status == LoginStatus.errorHomeNetworkOnly)],
    );

    blocTest<LoginBloc, LoginState>(
      'an ordinary disconnection says nothing at all here',
      // Only the refusal is the screen's business: every other phase is the
      // banner's job on the screens behind sign-in.
      build: () => LoginBloc(demo: true),
      act: (bloc) async {
        await Future<void>.delayed(Duration.zero);
        phase.emit(SessionPhase.disconnected);
        phase.emit(SessionPhase.connecting);
      },
      expect: () => <LoginState>[],
    );

    for (final (kind, link, expected) in [
      ('a link carrying the onion address', _onionLink, LoginStatus.errorHomeNetworkOnly),
      ('a link with a direct address only', _homeLink, LoginStatus.errorHomeNetworkOnly),
      ('something that is not a link', 'a-link', LoginStatus.errorServerMismatch),
    ]) {
      blocTest<LoginBloc, LoginState>(
        'the refusal outranks the "no channel" that sign-in reports after it, on $kind',
        // The real sequence again, with real links: what the refusal means
        // depends on the road the link took, and neither answer is "check your
        // connection".
        build: () {
          final auth = MockAuthRepository();
          when(auth.signIn(identifier: anyNamed('identifier'))).thenAnswer((_) async {
            phase.emit(SessionPhase.serverMismatch);
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return const RepositoryResult<bool>.error(exception: RepositoryException.connection);
          });
          getIt.registerSingleton<AuthRepository>(auth);
          return LoginBloc();
        },
        act: (bloc) async {
          bloc.add(LoginEvent.idChanged(link));
          await Future<void>.delayed(Duration.zero);
          bloc.add(const LoginEvent.signInRequested());
          await Future<void>.delayed(const Duration(milliseconds: 120));
        },
        verify: (bloc) => expect(bloc.state.status, expected),
      );
    }

    blocTest<LoginBloc, LoginState>(
      'the refusal outranks the "no channel" that sign-in reports after it',
      // THE REAL SEQUENCE, and the one the three tests around it miss by
      // emitting the phase with no sign-in in flight. The pin is checked inside
      // the handshake, before `pair` goes out, so the socket is already torn
      // down when signIn gets its answer and that answer can only be
      // `connection`. Mapped literally it becomes "check your connection" -
      // emitted AFTER the refusal, over a network that is working perfectly.
      build: () {
        final auth = MockAuthRepository();
        when(auth.signIn(identifier: anyNamed('identifier'))).thenAnswer((_) async {
          phase.emit(SessionPhase.serverMismatch);
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return const RepositoryResult<bool>.error(exception: RepositoryException.connection);
        });
        getIt.registerSingleton<AuthRepository>(auth);
        return LoginBloc();
      },
      act: (bloc) async {
        bloc.add(const LoginEvent.idChanged('a-link'));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const LoginEvent.signInRequested());
        await Future<void>.delayed(const Duration(milliseconds: 120));
      },
      verify: (bloc) {
        expect(bloc.state.status, LoginStatus.errorServerMismatch);
        expect(bloc.state.status, isNot(LoginStatus.errorNetwork));
      },
    );

    blocTest<LoginBloc, LoginState>(
      'an ordinary connection failure still says so, with no refusal anywhere',
      // The mutation of the case above: without a refusal the mapping must be
      // untouched, or every dead network would start blaming the server.
      build: () {
        final auth = MockAuthRepository();
        when(
          auth.signIn(identifier: anyNamed('identifier')),
        ).thenAnswer((_) async => const RepositoryResult<bool>.error(exception: RepositoryException.connection));
        getIt.registerSingleton<AuthRepository>(auth);
        return LoginBloc();
      },
      act: (bloc) async {
        bloc.add(const LoginEvent.idChanged('a-link'));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const LoginEvent.signInRequested());
        await Future<void>.delayed(const Duration(milliseconds: 120));
      },
      verify: (bloc) => expect(bloc.state.status, LoginStatus.errorNetwork),
    );

    blocTest<LoginBloc, LoginState>(
      'a refusal from an EARLIER attempt does not label the next failure',
      // The phase is terminal - it keeps saying serverMismatch until something
      // restarts the channel - so a later attempt that fails before it ever
      // dials (an unreadable keychain, say) would inherit the old verdict and
      // blame a server it never reached. A version-1 link, so that inheriting
      // it would read as "not home" just as wrongly as "wrong server".
      build: () {
        final auth = MockAuthRepository();
        when(
          auth.signIn(identifier: anyNamed('identifier')),
        ).thenAnswer((_) async => const RepositoryResult<bool>.error(exception: RepositoryException.internal));
        getIt.registerSingleton<AuthRepository>(auth);
        return LoginBloc();
      },
      act: (bloc) async {
        await Future<void>.delayed(Duration.zero);
        phase.emit(SessionPhase.serverMismatch); // a refusal, from before
        await Future<void>.delayed(const Duration(milliseconds: 20));
        bloc.add(const LoginEvent.idChanged(_homeLink)); // clears the screen
        await Future<void>.delayed(Duration.zero);
        bloc.add(const LoginEvent.signInRequested());
        await Future<void>.delayed(const Duration(milliseconds: 120));
      },
      verify: (bloc) => expect(bloc.state.status, LoginStatus.errorNetwork),
    );

    blocTest<LoginBloc, LoginState>(
      'typing clears it, because the next link may well be the right one',
      build: () => LoginBloc(demo: true),
      act: (bloc) async {
        await Future<void>.delayed(Duration.zero);
        phase.emit(SessionPhase.serverMismatch);
        await Future<void>.delayed(Duration.zero);
        bloc.add(const LoginEvent.idChanged('another-link'));
      },
      expect: () => [
        predicate<LoginState>((s) => s.status == LoginStatus.errorServerMismatch),
        predicate<LoginState>((s) => s.status == LoginStatus.idle && s.id == 'another-link'),
      ],
    );
  });

  // Until phase 045 every link has one road to its server for pairing, the
  // direct one (FR-019). Away from home not reaching it is the expected
  // outcome, so the screen says where pairing works instead of blaming the
  // network.
  group('LoginBloc and a link that works only at home (040)', () {
    late MockAuthRepository auth;

    setUp(() async {
      await configureDependencies(Environment.test);
      getIt.allowReassignment = true;
      auth = MockAuthRepository();
      getIt.registerSingleton<AuthRepository>(auth);
    });
    tearDown(() async => getIt.reset());

    blocTest<LoginBloc, LoginState>(
      'a link whose server did not answer says pairing works at home',
      build: () {
        when(
          auth.signIn(identifier: anyNamed('identifier')),
        ).thenAnswer((_) async => const RepositoryResult.error(exception: RepositoryException.connection));
        return LoginBloc();
      },
      act: (bloc) => bloc
        ..add(const LoginEvent.idChanged(_homeLink))
        ..add(const LoginEvent.signInRequested()),
      wait: const Duration(milliseconds: 300),
      expect: () => [
        predicate<LoginState>((s) => s.id == _homeLink),
        predicate<LoginState>((s) => s.status == LoginStatus.loading),
        // Still retryable: at home, the next press is the one that works.
        predicate<LoginState>((s) => s.status == LoginStatus.errorHomeNetworkOnly && s.canSubmit),
      ],
    );

    blocTest<LoginBloc, LoginState>(
      'a link carrying the onion address that reached nothing says pairing works at home too, until phase 045',
      // Its onion address is kept for after the pairing; the pairing itself
      // went only where a new device can be let in.
      build: () {
        when(
          auth.signIn(identifier: anyNamed('identifier')),
        ).thenAnswer((_) async => const RepositoryResult.error(exception: RepositoryException.connection));
        return LoginBloc();
      },
      act: (bloc) => bloc
        ..add(const LoginEvent.idChanged(_onionLink))
        ..add(const LoginEvent.signInRequested()),
      wait: const Duration(milliseconds: 300),
      verify: (bloc) => expect(bloc.state.status, LoginStatus.errorHomeNetworkOnly),
    );

    blocTest<LoginBloc, LoginState>(
      'a server that answered with an error is not a question of where the device is',
      // `internal` means the pairing reached the server and failed there.
      build: () {
        when(
          auth.signIn(identifier: anyNamed('identifier')),
        ).thenAnswer((_) async => const RepositoryResult.error(exception: RepositoryException.internal));
        return LoginBloc();
      },
      act: (bloc) => bloc
        ..add(const LoginEvent.idChanged(_homeLink))
        ..add(const LoginEvent.signInRequested()),
      wait: const Duration(milliseconds: 300),
      verify: (bloc) => expect(bloc.state.status, LoginStatus.errorNetwork),
    );

    for (final (exception, expected) in [
      (RepositoryException.invalidRequest, LoginStatus.errorFormat),
      (RepositoryException.notFound, LoginStatus.errorExpired),
      (RepositoryException.authentication, LoginStatus.errorRejected),
      // A link of a version above this build's (044, FR-017): update the app.
      (RepositoryException.unsupportedSchema, LoginStatus.errorNewerVersion),
    ]) {
      blocTest<LoginBloc, LoginState>(
        'a refusal of the link itself keeps its own message (${exception.name})',
        // The server answered, about the link: none of these is about where the
        // device is.
        build: () {
          when(auth.signIn(identifier: anyNamed('identifier'))).thenAnswer((_) async => RepositoryResult.error(exception: exception));
          return LoginBloc();
        },
        act: (bloc) => bloc
          ..add(const LoginEvent.idChanged(_homeLink))
          ..add(const LoginEvent.signInRequested()),
        wait: const Duration(milliseconds: 300),
        verify: (bloc) => expect(bloc.state.status, expected),
      );
    }
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
