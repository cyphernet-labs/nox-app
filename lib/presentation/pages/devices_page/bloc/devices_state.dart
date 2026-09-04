part of 'devices_bloc.dart';

@freezed
abstract class DevicesState with _$DevicesState {
  const DevicesState._();

  const factory DevicesState({
    @Default(true) bool loading,
    @Default(<DeviceModel>[]) List<DeviceModel> devices,
    @Default(false) bool failed,

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
