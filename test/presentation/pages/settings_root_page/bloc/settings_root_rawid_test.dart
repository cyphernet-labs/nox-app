import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/app/session_model.dart';
import 'package:nox_app/presentation/pages/settings_root_page/bloc/settings_root_bloc.dart';

import '../../../../utils/fake_session_repository.dart';

void main() {
  tearDown(getIt.reset);

  blocTest<SettingsRootBloc, SettingsRootState>(
    'shows the SERVER-minted author id, never the pairing token beside it',
    setUp: () => registerFakeSession(
      session: const SessionModel(identifier: 'pairing-token-xyz', authorId: 'u_1234567890abcdef', onboardingComplete: true),
    ),
    build: SettingsRootBloc.new,
    act: (bloc) => bloc.add(const SettingsRootEvent.initialize()),
    // The identifier slot now holds the pairing TOKEN. Showing that as "Your
    // ID" would put a credential on screen and into the clipboard.
    expect: () => [predicate<SettingsRootState>((s) => !s.initialLoading && s.rawId == 'u_1234567890abcdef' && !s.rawId.contains('token'))],
  );

  blocTest<SettingsRootBloc, SettingsRootState>(
    'with no session there is no id to show, and none is invented',
    setUp: () => registerFakeSession(session: null),
    build: SettingsRootBloc.new,
    act: (bloc) => bloc.add(const SettingsRootEvent.initialize()),
    expect: () => [predicate<SettingsRootState>((s) => !s.initialLoading && s.rawId.isEmpty)],
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
