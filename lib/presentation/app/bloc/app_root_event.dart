part of 'app_root_bloc.dart';

@freezed
sealed class AppRootEvent with _$AppRootEvent {
  const factory AppRootEvent.initialize() = Initialize;

  const factory AppRootEvent.setTheme({required ThemeMode themeMode}) = SetTheme;

  /// A new app-state emission off the reactive stream (two-phase apply input).
  const factory AppRootEvent.updateAppState({required RepositoryResult<AppStateModel> result}) = UpdateAppState;

  /// Releases the latest resolved state to the navigator (splash gate / immediate).
  const factory AppRootEvent.applyAppState() = ApplyAppState;
}
