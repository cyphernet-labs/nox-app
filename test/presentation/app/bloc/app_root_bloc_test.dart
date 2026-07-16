import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/app/app_state_model.dart';
import 'package:nox_app/domain/model/app/app_state_type.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/settings/settings_repository.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';

/// Settings store with a configurable theme read and write outcome — drives the
/// AppRootBloc theme-persistence branches (read-applied-on-Initialize, save-revert).
class _StubSettingsRepository implements SettingsRepository {
  _StubSettingsRepository({this.themeRead = ThemeMode.system, this.writeSucceeds = true});

  final ThemeMode themeRead;
  final bool writeSucceeds;

  @override
  Future<RepositoryResult<ThemeMode>> readThemeMode() async => RepositoryResult.success(data: themeRead);

  @override
  Future<RepositoryResult<bool>> setThemeMode(ThemeMode mode) async =>
      writeSucceeds ? const RepositoryResult.success(data: true) : const RepositoryResult.error(exception: RepositoryException.unknown);

  @override
  Future<RepositoryResult<bool>> readNotificationsEnabled() async => const RepositoryResult.success(data: true);

  @override
  Future<RepositoryResult<bool>> setNotificationsEnabled(bool enabled) async => const RepositoryResult.success(data: true);
}

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
      'an error emission still lands — releases the splash to a safe unauthorized (Login), never stalls',
      build: AppRootBloc.new,
      act: (bloc) => bloc.add(const AppRootEvent.updateAppState(result: RepositoryResult.error(exception: RepositoryException.unknown))),
      expect: () => [
        isA<AppRootState>()
            .having((s) => s.isReady, 'isReady', isTrue)
            .having((s) => s.lastAppState.state, 'lastAppState', AppStateType.unauthorized)
            // First emission → held behind the splash (not yet applied).
            .having((s) => s.appliedAppState.state, 'appliedAppState', AppStateType.init),
      ],
    );
  });

  group('AppRootBloc theme persistence', () {
    blocTest<AppRootBloc, AppRootState>(
      'applies the persisted theme on Initialize',
      setUp: () {
        getIt.allowReassignment = true;
        getIt.registerSingleton<SettingsRepository>(_StubSettingsRepository(themeRead: ThemeMode.dark));
      },
      build: AppRootBloc.new,
      act: (bloc) => bloc.add(const AppRootEvent.initialize()),
      wait: const Duration(milliseconds: 100),
      // The persisted theme survives later app-state emissions (copyWith preserves it).
      verify: (bloc) => expect(bloc.state.themeMode, ThemeMode.dark),
    );

    blocTest<AppRootBloc, AppRootState>(
      'a failed theme save reverts the theme and bumps the save-error tick',
      setUp: () {
        getIt.allowReassignment = true;
        getIt.registerSingleton<SettingsRepository>(_StubSettingsRepository(writeSucceeds: false));
      },
      build: AppRootBloc.new,
      act: (bloc) => bloc.add(const AppRootEvent.setTheme(themeMode: ThemeMode.dark)),
      expect: () => [
        // Optimistic apply — new theme, tick unchanged.
        isA<AppRootState>().having((s) => s.themeMode, 'themeMode', ThemeMode.dark).having((s) => s.settingsSaveErrorTick, 'tick', 0),
        // Save failed → revert to the previous theme and bump the tick.
        isA<AppRootState>().having((s) => s.themeMode, 'themeMode', ThemeMode.system).having((s) => s.settingsSaveErrorTick, 'tick', 1),
      ],
    );
  });
}
