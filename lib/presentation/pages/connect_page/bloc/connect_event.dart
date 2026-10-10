part of 'connect_bloc.dart';

@freezed
sealed class ConnectEvent with _$ConnectEvent {
  const factory ConnectEvent.serverAddressChanged(String value) = ServerAddressChanged;

  const factory ConnectEvent.onionAddressChanged(String value) = OnionAddressChanged;

  const factory ConnectEvent.useTorChanged(bool value) = UseTorChanged;

  /// `Connect` pressed.
  const factory ConnectEvent.connectRequested() = ConnectRequested;

  /// Where the connection stands - how the cause of a failing attempt
  /// reaches the screen while the attempt is still under way.
  const factory ConnectEvent.connectionStatusChanged(ConnectionStatus status) = ConnectionStatusChanged;
}
