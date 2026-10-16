part of 'connection_settings_bloc.dart';

@freezed
abstract class ConnectionSettingsState with _$ConnectionSettingsState {
  const ConnectionSettingsState._();

  const factory ConnectionSettingsState({
    /// Nothing read yet.
    @Default(true) bool loading,

    /// The field "Server address" as typed, and as it stands applied: the
    /// person's own edit, else the server's public address, else the link's.
    @Default('') String serverAddress,
    @Default('') String appliedServerAddress,

    /// The field "Onion address" as typed (`<56>.onion`), and as it stands
    /// applied; empty for none.
    @Default('') String onionAddress,
    @Default('') String appliedOnionAddress,

    /// What the fields would show with no hand edit at all - what the server
    /// says, else the link: a value saved equal to it is no edit.
    @Default('') String serverDefaultAddress,
    @Default('') String serverDefaultOnion,

    /// `Use Tor`, as applied.
    @Default(false) bool useTor,

    /// The typed values fail the format check.
    @Default(false) bool serverAddressInvalid,
    @Default(false) bool onionAddressInvalid,

    /// A write is under way.
    @Default(false) bool saving,

    /// The last write did not land.
    @Default(false) bool saveFailed,

    /// The connection is down: the line above the fields says so.
    @Default(false) bool offline,

    /// Why, when that is known (phase 045).
    ConnectionProblem? problem,
  }) = _ConnectionSettingsState;

  /// Something typed differs from what is applied.
  bool get changed => serverAddress.trim() != appliedServerAddress || onionAddress.trim() != appliedOnionAddress;

  /// `Save` is offered for a change that passes the format check (FR-014).
  bool get canSave => !loading && !saving && changed && !serverAddressInvalid && !onionAddressInvalid;

  /// An error shows under a field the person has changed - `Save` is off
  /// while it stands, and would otherwise say nothing about why.
  bool get showServerAddressError => serverAddressInvalid && serverAddress.trim() != appliedServerAddress;

  bool get showOnionAddressError => onionAddressInvalid && onionAddress.trim() != appliedOnionAddress;
}
