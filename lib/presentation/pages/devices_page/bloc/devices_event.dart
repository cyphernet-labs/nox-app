part of 'devices_bloc.dart';

@freezed
sealed class DevicesEvent with _$DevicesEvent {
  const factory DevicesEvent.initialize() = DevicesInitialize;

  const factory DevicesEvent.revokeRequested(String deviceKey) = DevicesRevokeRequested;

  const factory DevicesEvent.inviteRequested() = DevicesInviteRequested;

  const factory DevicesEvent.inviteDismissed() = DevicesInviteDismissed;
}
