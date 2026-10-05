part of 'connection_indicator_bloc.dart';

@freezed
abstract class ConnectionIndicatorState with _$ConnectionIndicatorState {
  const ConnectionIndicatorState._();

  const factory ConnectionIndicatorState({required ConnectionStatus status}) = _ConnectionIndicatorState;

  /// Nothing to say: direct and current, offline (the banner speaks), or a
  /// terminal state (a banner speaks).
  bool get isEmpty => !status.showsConnecting && !status.showsTorBadge;
}
