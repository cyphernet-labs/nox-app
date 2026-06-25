import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/pages/login_page/bloc/login_bloc.dart';

void main() {
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
        predicate<LoginState>((s) => s.status == LoginStatus.errorNetwork && s.errorText != null),
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
}
