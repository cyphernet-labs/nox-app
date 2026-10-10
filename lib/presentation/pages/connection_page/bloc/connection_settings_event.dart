part of 'connection_settings_bloc.dart';

@freezed
sealed class ConnectionSettingsEvent with _$ConnectionSettingsEvent {
  /// The section opened: read what is stored, and follow it.
  const factory ConnectionSettingsEvent.initialize() = ConnectionSettingsInitialize;

  const factory ConnectionSettingsEvent.serverAddressChanged(String value) = ConnectionSettingsServerAddressChanged;

  const factory ConnectionSettingsEvent.onionAddressChanged(String value) = ConnectionSettingsOnionAddressChanged;

  /// `Save` pressed: the two address fields are applied.
  const factory ConnectionSettingsEvent.saveRequested() = ConnectionSettingsSaveRequested;

  /// `Use Tor` switched: applied at once.
  const factory ConnectionSettingsEvent.useTorChanged(bool value) = ConnectionSettingsUseTorChanged;

  /// What is stored changed - the server stated its addresses, say.
  const factory ConnectionSettingsEvent.storedChanged(ServerAddresses stored) = ConnectionSettingsStoredChanged;

  /// Where the connection stands, for the line above the fields.
  const factory ConnectionSettingsEvent.connectionStatusChanged(ConnectionStatus status) = ConnectionSettingsConnectionStatusChanged;
}
