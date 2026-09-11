part of 'devices_bloc.dart';

@freezed
sealed class DevicesEvent with _$DevicesEvent {
  /// [cause] is WHY the list is being read, and it decides two different
  /// things: whether a spinner is allowed, and whether a failure is news.
  ///
  /// It is an enum rather than a flag because folding the two questions into
  /// one boolean has now produced a defect twice. A flag that starts life
  /// meaning "do not show a spinner" is read a round later as "say nothing at
  /// all", and the failure of a read the person is actually waiting on
  /// disappears with it.
  const factory DevicesEvent.initialize({@Default(DevicesReadCause.opened) DevicesReadCause cause}) = DevicesInitialize;

  const factory DevicesEvent.revokeRequested(String deviceKey) = DevicesRevokeRequested;

  const factory DevicesEvent.inviteRequested() = DevicesInviteRequested;

  const factory DevicesEvent.inviteDismissed() = DevicesInviteDismissed;

  /// The server said another device of this person was paired.
  const factory DevicesEvent.deviceListChanged() = DevicesDeviceListChanged;

  /// The live channel came back after a break.
  const factory DevicesEvent.connectionRestored() = DevicesConnectionRestored;
}

/// Why the list is being read. The three answers differ in what the person
/// should see, and nothing else about the read differs at all.
enum DevicesReadCause {
  /// The section was just opened. Nothing is on screen yet, so a spinner is
  /// honest and a failure is the entire answer.
  opened,

  /// The person asked for something that changes the list — a revoke — and this
  /// read is how the change is confirmed. The list stays up, because they are
  /// watching it change; but a failure is theirs to see, because they asked.
  /// Silence here leaves a device they meant to cut off sitting in the list
  /// with nothing on screen to say the confirmation never came.
  asked,

  /// The screen noticed by itself: a pairing was announced, or the channel came
  /// back. Nobody asked, so a read that FAILS leaves the screen exactly as it
  /// found it — it neither raises an error nor takes down one already up.
  ///
  /// A read that SUCCEEDS clears the error like any other, whoever started it:
  /// the server has answered, and "we could not load your devices" has stopped
  /// being true.
  noticed,
}
