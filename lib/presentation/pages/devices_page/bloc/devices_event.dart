part of 'devices_bloc.dart';

@freezed
sealed class DevicesEvent with _$DevicesEvent {
  /// [refresh] means "the list is already on screen, bring it up to date".
  ///
  /// The difference is visible: a first load may show a spinner, a refresh must
  /// not — the screen would blank out under somebody who did not ask for
  /// anything, and on a flapping link it would strobe.
  const factory DevicesEvent.initialize({@Default(false) bool refresh}) = DevicesInitialize;

  const factory DevicesEvent.revokeRequested(String deviceKey) = DevicesRevokeRequested;

  const factory DevicesEvent.inviteRequested() = DevicesInviteRequested;

  const factory DevicesEvent.inviteDismissed() = DevicesInviteDismissed;

  /// The server said another device of this person was paired.
  const factory DevicesEvent.deviceListChanged() = DevicesDeviceListChanged;

  /// The live channel came back after a break.
  const factory DevicesEvent.connectionRestored() = DevicesConnectionRestored;
}
