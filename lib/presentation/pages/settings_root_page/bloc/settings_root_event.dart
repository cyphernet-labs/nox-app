part of 'settings_root_bloc.dart';

@freezed
sealed class SettingsRootEvent with _$SettingsRootEvent {
  /// Load the identity (stub) → clears Initial-loading.
  const factory SettingsRootEvent.initialize() = SettingsInitialize;

  /// Tap on the name / edit pencil → enter inline edit.
  const factory SettingsRootEvent.nameEditStarted() = NameEditStarted;

  /// Name draft changed (immediate charset / empty feedback).
  const factory SettingsRootEvent.nameChanged(String name) = SettingsNameChanged;

  /// Debounced uniqueness check for [name].

  /// Save the draft (Enter / Done / blur) — commits only when valid.
  const factory SettingsRootEvent.nameSubmitted() = NameSubmitted;

  /// Cancel inline edit → revert to the committed name.
  const factory SettingsRootEvent.nameEditCancelled() = NameEditCancelled;

  /// Toggle the masked ↔ revealed identifier (mobile only).
  const factory SettingsRootEvent.idRevealToggled() = IdRevealToggled;
}
