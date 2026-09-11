part of 'devices_bloc.dart';

@freezed
abstract class DevicesState with _$DevicesState {
  const DevicesState._();

  const factory DevicesState({
    @Default(true) bool loading,
    @Default(<DeviceModel>[]) List<DeviceModel> devices,

    /// The LIST could not be read. Drives the whole-screen error when there is
    /// nothing to show, and a notice above the list when there is.
    @Default(false) bool failed,

    /// Something the person ASKED FOR did not happen — a revoke, or the logout
    /// a revoke of this device turns into.
    ///
    /// Separate from [failed] because the two answer different questions, and
    /// 038 made the difference matter: the screen now re-reads the list on its
    /// own, and a background read that succeeds would otherwise "answer" a
    /// question nobody asked it — quietly clearing the notice that a revoke
    /// failed, leaving a device the person meant to cut off still authorised
    /// and nothing on screen saying so.
    @Default(false) bool actionFailed,

    /// The invite link currently on screen, or null. Held in state rather than
    /// re-fetched, because every fetch burns a new token on the server.
    String? inviteLink,
    @Default(false) bool inviteFailed,
  }) = _DevicesState;

  /// Everything except this device. The current one is shown apart, because
  /// revoking it is a logout and reads differently.
  List<DeviceModel> get others => devices.where((d) => !d.isCurrent).toList();

  DeviceModel? get current => devices.where((d) => d.isCurrent).firstOrNull;
}
