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

    /// The device whose revoke did not happen, or null if none did.
    ///
    /// A key rather than a flag, because the notice belongs to ONE device. With
    /// a flag, starting a revoke of a DIFFERENT device took down a notice that
    /// was still true: the first device stayed authorised, and the screen said
    /// nothing about it ever again.
    ///
    /// Separate from [failed] because the two answer different questions, and
    /// 038 made the difference matter: the screen now re-reads the list on its
    /// own, and a read that succeeds would otherwise "answer" a question nobody
    /// asked it — quietly clearing the notice that a revoke failed.
    String? actionFailedKey,

    /// The invite link currently on screen, or null. Held in state rather than
    /// re-fetched, because every fetch burns a new token on the server.
    String? inviteLink,
    @Default(false) bool inviteFailed,
  }) = _DevicesState;

  /// Whether a revoke the person asked for did not happen. The screen shows one
  /// notice, so which device it was does not reach the widget - only the fact,
  /// and the key that keeps the fact honest.
  bool get actionFailed => actionFailedKey != null;

  /// Everything except this device. The current one is shown apart, because
  /// revoking it is a logout and reads differently.
  List<DeviceModel> get others => devices.where((d) => !d.isCurrent).toList();

  DeviceModel? get current => devices.where((d) => d.isCurrent).firstOrNull;
}
