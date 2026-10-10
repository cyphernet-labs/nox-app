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
    // Increments on each failed settings save (theme) so a listener can surface the
    // "Could not save. Try again." notice; the theme itself is reverted on failure.
    @Default(0) int settingsSaveErrorTick,

    /// The request to join this person's devices that waits for this device's
    /// answer now - the oldest, when there are several - or null (phase 046).
    /// AppRoot asks about it in a dialog over whatever screen is up.
    PairRequest? pairRequest,

    /// The answer to [pairRequest] on its way - `true` for Allow, `false` for
    /// Deny - or null when none is.
    bool? pairAnswering,

    /// The last answer to [pairRequest] did not get through; both buttons
    /// stay, to give it again.
    @Default(false) bool pairAnswerFailed,
  }) = _AppRootState;

  factory AppRootState.initial() =>
      AppRootState(themeMode: ThemeMode.system, lastAppState: AppStateModel.init(), appliedAppState: AppStateModel.init());
}
