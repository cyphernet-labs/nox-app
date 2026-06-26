import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/app/app_state_model.dart';
import 'package:nox_app/domain/model/app/app_state_type.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';

void main() {
  // The error branch of _onUpdateAppState logs via the global LogRepository, so the
  // DI graph must be up (test-env serves a real LogRepository).
  setUp(() async {
    await configureDependencies(Environment.test);
    await getIt.allReady();
  });

  tearDown(() async {
    await getIt.reset();
  });

  RepositoryResult<AppStateModel> resolved(AppStateType state) =>
      RepositoryResult<AppStateModel>.success(data: AppStateModel(state: state, session: null));

  group('AppRootBloc two-phase apply', () {
    blocTest<AppRootBloc, AppRootState>(
      'holds the first resolved state behind the splash until ApplyAppState',
      build: AppRootBloc.new,
      act: (bloc) => bloc
        ..add(AppRootEvent.updateAppState(result: resolved(AppStateType.unauthorized)))
        ..add(const AppRootEvent.applyAppState()),
      expect: () => [
        isA<AppRootState>()
            .having((s) => s.isReady, 'isReady', isTrue)
            .having((s) => s.lastAppState.state, 'lastAppState', AppStateType.unauthorized)
            .having((s) => s.appliedAppState.state, 'appliedAppState (held)', AppStateType.init),
        isA<AppRootState>().having((s) => s.appliedAppState.state, 'appliedAppState (released)', AppStateType.unauthorized),
      ],
    );

    blocTest<AppRootBloc, AppRootState>(
      'applies later transitions immediately once ready',
      build: AppRootBloc.new,
      act: (bloc) => bloc
        ..add(AppRootEvent.updateAppState(result: resolved(AppStateType.unauthorized)))
        ..add(const AppRootEvent.applyAppState())
        ..add(AppRootEvent.updateAppState(result: resolved(AppStateType.authorized))),
      verify: (bloc) {
        expect(bloc.state.appliedAppState.state, AppStateType.authorized);
        expect(bloc.state.lastAppState.state, AppStateType.authorized);
      },
    );

    blocTest<AppRootBloc, AppRootState>(
      'ignores an error emission (no data)',
      build: AppRootBloc.new,
      act: (bloc) => bloc.add(const AppRootEvent.updateAppState(result: RepositoryResult.error(exception: RepositoryException.unknown))),
      expect: () => const <AppRootState>[],
    );
  });
}
