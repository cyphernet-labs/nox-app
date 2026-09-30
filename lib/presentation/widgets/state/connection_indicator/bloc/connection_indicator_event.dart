part of 'connection_indicator_bloc.dart';

@freezed
sealed class ConnectionIndicatorEvent with _$ConnectionIndicatorEvent {
  /// Starts following the connection status.
  const factory ConnectionIndicatorEvent.started() = Started;

  /// The connection status changed.
  const factory ConnectionIndicatorEvent.statusChanged(ConnectionStatus status) = StatusChanged;
}
