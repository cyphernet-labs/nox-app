import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/presentation/pages/settings_root_page/bloc/settings_root_bloc.dart';

import '../../../../utils/fake_session_repository.dart';

void main() {
  group('SettingsRootBloc', () {
    setUp(registerFakeSession);
    tearDown(getIt.reset);

    blocTest<SettingsRootBloc, SettingsRootState>(
      'initialize clears the initial-loading flag and loads the identifier',
      build: SettingsRootBloc.new,
      act: (bloc) => bloc.add(const SettingsRootEvent.initialize()),
      expect: () => [predicate<SettingsRootState>((s) => !s.initialLoading && s.rawId == kTestIdentifier)],
    );

    blocTest<SettingsRootBloc, SettingsRootState>(
      'name-edit started enters editing with a valid (pristine) draft',
      build: SettingsRootBloc.new,
      act: (bloc) => bloc.add(const SettingsRootEvent.nameEditStarted()),
      expect: () => [predicate<SettingsRootState>((s) => s.editing && s.status == SettingsNameStatus.valid)],
    );

    blocTest<SettingsRootBloc, SettingsRootState>(
      'rejects an invalid charset immediately, without a server check',
      build: SettingsRootBloc.new,
      act: (bloc) => bloc.add(const SettingsRootEvent.nameChanged('bad name!')),
      expect: () => [predicate<SettingsRootState>((s) => s.status == SettingsNameStatus.invalidCharset)],
    );

    blocTest<SettingsRootBloc, SettingsRootState>(
      'an empty draft is not committable and shows no error',
      build: SettingsRootBloc.new,
      act: (bloc) => bloc.add(const SettingsRootEvent.nameChanged('')),
      expect: () => [predicate<SettingsRootState>((s) => s.status == SettingsNameStatus.idle && !s.canSave)],
    );

    blocTest<SettingsRootBloc, SettingsRootState>(
      'a free valid name resolves to valid after the debounced check',
      build: SettingsRootBloc.new,
      act: (bloc) => bloc.add(const SettingsRootEvent.nameChanged('Freename')),
      wait: const Duration(milliseconds: 700),
      expect: () => [
        predicate<SettingsRootState>((s) => s.status == SettingsNameStatus.checking),
        predicate<SettingsRootState>((s) => s.status == SettingsNameStatus.valid && s.canSave),
      ],
    );

    blocTest<SettingsRootBloc, SettingsRootState>(
      'a taken name resolves to taken (case-sensitive)',
      build: SettingsRootBloc.new,
      act: (bloc) => bloc.add(const SettingsRootEvent.nameChanged('NOX')),
      wait: const Duration(milliseconds: 700),
      expect: () => [
        predicate<SettingsRootState>((s) => s.status == SettingsNameStatus.checking),
        predicate<SettingsRootState>((s) => s.status == SettingsNameStatus.taken),
      ],
    );

    blocTest<SettingsRootBloc, SettingsRootState>(
      'the unchanged current name stays valid with no server check',
      build: SettingsRootBloc.new,
      act: (bloc) => bloc.add(const SettingsRootEvent.nameChanged('User7421')),
      expect: () => [predicate<SettingsRootState>((s) => s.status == SettingsNameStatus.valid)],
    );

    blocTest<SettingsRootBloc, SettingsRootState>(
      'submitting a valid draft commits the name and leaves edit mode',
      build: SettingsRootBloc.new,
      seed: () => const SettingsRootState(name: 'User7421', draftName: 'Freename', editing: true, status: SettingsNameStatus.valid),
      act: (bloc) => bloc.add(const SettingsRootEvent.nameSubmitted()),
      expect: () => [predicate<SettingsRootState>((s) => s.name == 'Freename' && !s.editing && s.status == SettingsNameStatus.idle)],
    );

    blocTest<SettingsRootBloc, SettingsRootState>(
      'cancelling edit reverts the draft to the committed name',
      build: SettingsRootBloc.new,
      seed: () => const SettingsRootState(name: 'User7421', draftName: 'Half', editing: true, status: SettingsNameStatus.checking),
      act: (bloc) => bloc.add(const SettingsRootEvent.nameEditCancelled()),
      expect: () => [predicate<SettingsRootState>((s) => !s.editing && s.draftName == 'User7421' && s.status == SettingsNameStatus.idle)],
    );

    blocTest<SettingsRootBloc, SettingsRootState>(
      'toggles the identifier reveal',
      build: SettingsRootBloc.new,
      act: (bloc) => bloc.add(const SettingsRootEvent.idRevealToggled()),
      expect: () => [predicate<SettingsRootState>((s) => s.idRevealed)],
    );
  });

  // Feature 015 — the display label is loaded from and persisted to the REAL session
  // (mock-backed store), so these use the test-env DI rather than the read-only fake.
  group('identity label persistence (feature 015)', () {
    setUp(() async => configureDependencies(Environment.test));
    tearDown(getIt.reset);

    Future<void> signIn(String label) async {
      await getIt<SessionRepository>().saveIdentifier(identifier: 'sess-abc', onboardingComplete: true, label: label);
    }

    blocTest<SettingsRootBloc, SettingsRootState>(
      'initialize loads the session display label into name',
      setUp: () => signIn('Alice'),
      build: SettingsRootBloc.new,
      act: (bloc) => bloc.add(const SettingsRootEvent.initialize()),
      wait: const Duration(milliseconds: 100),
      verify: (bloc) {
        expect(bloc.state.name, 'Alice'); // the chosen label, not the compile-time default
        expect(bloc.state.rawId, 'sess-abc');
      },
    );

    test('a valid confirmed rename persists the new label to the session', () async {
      await signIn('Alice');
      final bloc = SettingsRootBloc()..add(const SettingsRootEvent.initialize());
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      bloc.add(const SettingsRootEvent.nameEditStarted());
      bloc.add(const SettingsRootEvent.nameChanged('Freename'));
      await Future<void>.delayed(const Duration(milliseconds: 700)); // debounced availability → valid
      expect(bloc.state.status, SettingsNameStatus.valid);

      bloc.add(const SettingsRootEvent.nameSubmitted());
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(bloc.state.name, 'Freename'); // committed in the bloc
      expect((await getIt<SessionRepository>().readSession()).data!.label, 'Freename'); // and persisted

      // Simulate a full restart: discard the DI graph and re-read through a FRESH
      // repository over the persisted store — the renamed label is still there (FR-007/SC-002).
      await getIt.reset();
      await configureDependencies(Environment.test);
      expect((await getIt<SessionRepository>().readSession()).data!.label, 'Freename');
    });

    test('a charset-valid but already-taken label is never persisted (FR-008)', () async {
      await signIn('Alice');
      final bloc = SettingsRootBloc()..add(const SettingsRootEvent.initialize());
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      bloc.add(const SettingsRootEvent.nameEditStarted());
      bloc.add(const SettingsRootEvent.nameChanged('NOX')); // valid charset, but a taken label
      await Future<void>.delayed(const Duration(milliseconds: 700)); // debounced uniqueness check → taken
      expect(bloc.state.status, SettingsNameStatus.taken);

      bloc.add(const SettingsRootEvent.nameSubmitted()); // canSave == false → no-op
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect((await getIt<SessionRepository>().readSession()).data!.label, 'Alice'); // unchanged
    });

    test('an invalid draft is never persisted', () async {
      await signIn('Alice');
      final bloc = SettingsRootBloc()..add(const SettingsRootEvent.initialize());
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      bloc.add(const SettingsRootEvent.nameEditStarted());
      bloc.add(const SettingsRootEvent.nameChanged('bad name!')); // invalid charset → not committable
      await Future<void>.delayed(const Duration(milliseconds: 100));
      bloc.add(const SettingsRootEvent.nameSubmitted()); // canSave == false → no-op
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect((await getIt<SessionRepository>().readSession()).data!.label, 'Alice'); // unchanged
    });
  });
}
