part of 'app_root_bloc.dart';

@freezed
abstract class AppRootState with _$AppRootState {
  const factory AppRootState({required ThemeMode themeMode}) = _AppRootState;
}
