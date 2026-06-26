part of 'app_root_bloc.dart';

/// App-level state: theme + the two-phase app-state spine. `lastAppState` tracks
/// every stream emission; `appliedAppState` is the value currently applied to the
/// navigator (released by [ApplyAppState]); `isReady` flips true on the first
/// emission carrying data. The two-phase split holds the first navigation behind
/// the splash reveal (see `docs/app-state-flow-migration.md` §5.1).
@freezed
abstract class AppRootState with _$AppRootState {
  const factory AppRootState({
    required ThemeMode themeMode,
    required AppStateModel lastAppState,
    required AppStateModel appliedAppState,
    @Default(false) bool isReady,
  }) = _AppRootState;

  factory AppRootState.initial() =>
      AppRootState(themeMode: ThemeMode.system, lastAppState: AppStateModel.init(), appliedAppState: AppStateModel.init());
}
