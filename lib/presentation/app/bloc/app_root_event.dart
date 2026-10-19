part of 'app_root_bloc.dart';

@freezed
sealed class AppRootEvent with _$AppRootEvent {
  const factory AppRootEvent.initialize() = Initialize;

  const factory AppRootEvent.setTheme({required ThemeMode themeMode}) = SetTheme;

  /// A new app-state emission off the reactive stream (two-phase apply input).
  const factory AppRootEvent.updateAppState({required RepositoryResult<AppStateModel> result}) = UpdateAppState;

  /// Releases the latest resolved state to the navigator (splash gate / immediate).
  const factory AppRootEvent.applyAppState() = ApplyAppState;

  /// The requests to join that wait for this device's answer changed (phase
  /// 046).
  const factory AppRootEvent.pairRequestsChanged(List<PairRequest> requests) = PairRequestsChanged;

  /// `Allow` or `Deny` pressed in the dialog asking about [requestId] (phase
  /// 046).
  const factory AppRootEvent.pairRequestAnswered({required String requestId, required bool allow}) = PairRequestAnswered;
}
