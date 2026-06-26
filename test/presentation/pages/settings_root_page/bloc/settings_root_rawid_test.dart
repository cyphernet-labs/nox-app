import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/app/session_model.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/presentation/pages/settings_root_page/bloc/settings_root_bloc.dart';

/// Minimal session double — only `readSession` is exercised by `_onInitialize`.
class _StubSession implements SessionRepository {
  _StubSession(this._session);

  final SessionModel? _session;

  @override
  Future<RepositoryResult<SessionModel?>> readSession() async => RepositoryResult<SessionModel?>.success(data: _session);

  @override
  Future<RepositoryResult<bool>> saveIdentifier({required String identifier, required bool onboardingComplete, String? label}) =>
      throw UnimplementedError();

  @override
  Future<RepositoryResult<bool>> setOnboardingComplete({String? label}) => throw UnimplementedError();

  @override
  Future<RepositoryResult<bool>> clear() => throw UnimplementedError();
}

void main() {
  void registerSession(SessionModel? session) {
    if (getIt.isRegistered<SessionRepository>()) getIt.unregister<SessionRepository>();
    getIt.registerSingleton<SessionRepository>(_StubSession(session));
  }

  tearDown(() => getIt.reset());

  blocTest<SettingsRootBloc, SettingsRootState>(
    'initialize loads the real identifier from the session into rawId (FR-014)',
    setUp: () => registerSession(const SessionModel(identifier: 'real-id-xyz', onboardingComplete: true)),
    build: SettingsRootBloc.new,
    act: (bloc) => bloc.add(const SettingsRootEvent.initialize()),
    expect: () => [predicate<SettingsRootState>((s) => !s.initialLoading && s.rawId == 'real-id-xyz')],
  );

  blocTest<SettingsRootBloc, SettingsRootState>(
    'falls back to the stub identifier when the session has no id (never an empty QR)',
    setUp: () => registerSession(null),
    build: SettingsRootBloc.new,
    act: (bloc) => bloc.add(const SettingsRootEvent.initialize()),
    expect: () => [predicate<SettingsRootState>((s) => !s.initialLoading && s.rawId == SettingsRootBloc.mockRawId)],
  );
}
