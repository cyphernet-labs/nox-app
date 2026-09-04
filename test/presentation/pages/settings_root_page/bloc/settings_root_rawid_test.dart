import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/app/session_model.dart';
import 'package:nox_app/general/identity_mock_data.dart';
import 'package:nox_app/presentation/pages/settings_root_page/bloc/settings_root_bloc.dart';

import '../../../../utils/fake_session_repository.dart';

void main() {
  tearDown(getIt.reset);

  blocTest<SettingsRootBloc, SettingsRootState>(
    'initialize loads the real identifier from the session into rawId (FR-014)',
    setUp: () => registerFakeSession(session: const SessionModel(identifier: 'real-id-xyz', onboardingComplete: true)),
    build: SettingsRootBloc.new,
    act: (bloc) => bloc.add(const SettingsRootEvent.initialize()),
    expect: () => [predicate<SettingsRootState>((s) => !s.initialLoading && s.rawId == 'real-id-xyz')],
  );

  blocTest<SettingsRootBloc, SettingsRootState>(
    'with no session the shown id is the resolver fallback, not a fabricated secret',
    setUp: () => registerFakeSession(session: null),
    build: SettingsRootBloc.new,
    act: (bloc) => bloc.add(const SettingsRootEvent.initialize()),
    // The id is PUBLIC since feature 032 - a person is recognised by a paired
    // key, not by this string - so there is no secret here to withhold. What
    // still matters is that nothing invents one.
    expect: () => [predicate<SettingsRootState>((s) => !s.initialLoading && s.rawId == IdentityMockData.fallbackOwnId)],
  );

  blocTest<SettingsRootBloc, SettingsRootState>(
    'a read error shows nothing rather than inventing an id',
    setUp: () => registerFakeSession(fail: true),
    build: SettingsRootBloc.new,
    act: (bloc) => bloc.add(const SettingsRootEvent.initialize()),
    // Deliberately not the fallback: a session that could not be read is not
    // the same as a session that has no id, and guessing here would show
    // somebody an id that is not theirs.
    expect: () => [predicate<SettingsRootState>((s) => !s.initialLoading && s.rawId.isEmpty)],
  );
}
