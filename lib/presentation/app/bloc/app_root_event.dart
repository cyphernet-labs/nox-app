part of 'app_root_bloc.dart';

@freezed
sealed class AppRootEvent with _$AppRootEvent {
  const factory AppRootEvent.initialize() = Initialize;

  const factory AppRootEvent.setTheme({required ThemeMode themeMode}) = SetTheme;
}
