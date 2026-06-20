import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/presentation/pages/set_username_page/bloc/set_username_bloc.dart';

void main() {
  group('SetUsernameBloc', () {
    blocTest<SetUsernameBloc, SetUsernameState>(
      'rejects an invalid charset immediately, without a server check',
      build: SetUsernameBloc.new,
      act: (bloc) => bloc.add(const SetUsernameEvent.nameChanged('bad name!')),
      expect: () => [predicate<SetUsernameState>((s) => s.status == UsernameStatus.invalidCharset && s.errorText != null)],
    );

    blocTest<SetUsernameBloc, SetUsernameState>(
      'empty name disables submit',
      build: SetUsernameBloc.new,
      act: (bloc) => bloc.add(const SetUsernameEvent.nameChanged('')),
      expect: () => [predicate<SetUsernameState>((s) => s.status == UsernameStatus.empty && !s.canSubmit)],
    );

    blocTest<SetUsernameBloc, SetUsernameState>(
      'a free valid name resolves to valid after the debounced check',
      build: SetUsernameBloc.new,
      act: (bloc) => bloc.add(const SetUsernameEvent.nameChanged('Freename')),
      wait: const Duration(milliseconds: 700),
      expect: () => [
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.checking),
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.valid && s.canSubmit),
      ],
    );

    blocTest<SetUsernameBloc, SetUsernameState>(
      'a taken name resolves to taken',
      build: SetUsernameBloc.new,
      act: (bloc) => bloc.add(const SetUsernameEvent.nameChanged('NOX')),
      wait: const Duration(milliseconds: 700),
      expect: () => [
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.checking),
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.taken && s.errorText != null),
      ],
    );

    blocTest<SetUsernameBloc, SetUsernameState>(
      'uniqueness is case-sensitive: "nox" is free even though "NOX" is taken',
      build: SetUsernameBloc.new,
      act: (bloc) => bloc.add(const SetUsernameEvent.nameChanged('nox')),
      wait: const Duration(milliseconds: 700),
      expect: () => [
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.checking),
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.valid),
      ],
    );

    blocTest<SetUsernameBloc, SetUsernameState>(
      'Done with the success outcome navigates',
      build: SetUsernameBloc.new,
      act: (bloc) => bloc.add(const SetUsernameEvent.doneRequested()),
      wait: const Duration(milliseconds: 500),
      expect: () => [
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.submitting),
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.navSuccess),
      ],
    );

    blocTest<SetUsernameBloc, SetUsernameState>(
      'Done with the race-taken outcome shows an inline error',
      build: SetUsernameBloc.new,
      act: (bloc) => bloc.add(const SetUsernameEvent.doneRequested(outcome: UsernameOutcome.raceTaken)),
      wait: const Duration(milliseconds: 500),
      expect: () => [
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.submitting),
        predicate<SetUsernameState>((s) => s.status == UsernameStatus.raceTaken && s.errorText != null),
      ],
    );
  });
}
