import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/app/session_model.dart';
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
    'a session with no id yields an empty rawId — never fabricates a fake scannable QR',
    setUp: () => registerFakeSession(session: null),
    build: SettingsRootBloc.new,
    act: (bloc) => bloc.add(const SettingsRootEvent.initialize()),
    expect: () => [predicate<SettingsRootState>((s) => !s.initialLoading && s.rawId.isEmpty)],
  );

  blocTest<SettingsRootBloc, SettingsRootState>(
    'a read error yields an empty rawId (fails soft, no fabricated identity)',
    setUp: () => registerFakeSession(fail: true),
    build: SettingsRootBloc.new,
    act: (bloc) => bloc.add(const SettingsRootEvent.initialize()),
    expect: () => [predicate<SettingsRootState>((s) => !s.initialLoading && s.rawId.isEmpty)],
  );
}
