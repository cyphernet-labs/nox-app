part of 'devices_bloc.dart';

@freezed
sealed class DevicesEvent with _$DevicesEvent {
  const factory DevicesEvent.initialize() = DevicesInitialize;

  const factory DevicesEvent.revokeRequested(String deviceKey) = DevicesRevokeRequested;

  const factory DevicesEvent.inviteRequested() = DevicesInviteRequested;

  const factory DevicesEvent.inviteDismissed() = DevicesInviteDismissed;

  /// The server said another device of this person was paired.
  const factory DevicesEvent.deviceListChanged() = DevicesDeviceListChanged;

  /// The live channel came back after a break.
  const factory DevicesEvent.connectionRestored() = DevicesConnectionRestored;
}
