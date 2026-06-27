part of 'settings_root_bloc.dart';

/// Inline name-edit status (7.1 identity card). Mirrors the 2.3 vocabulary.
enum SettingsNameStatus { idle, checking, valid, invalidCharset, taken }

@freezed
abstract class SettingsRootState with _$SettingsRootState {
  const SettingsRootState._();

  const factory SettingsRootState({
    @Default(true) bool initialLoading,
    @Default(Constants.defaultUserLabel) String name,
    // The user's own identifier (Your ID), encoded into the Show QR surface (7.1,
    // FR-014). Loaded from the session on initialize; falls back to the stub.
    @Default('') String rawId,
    @Default('') String draftName,
    @Default(false) bool editing,
    @Default(SettingsNameStatus.idle) SettingsNameStatus status,
    @Default(false) bool idRevealed,
  }) = _SettingsRootState;

  bool get isChecking => status == SettingsNameStatus.checking;

  /// Save (Enter/Done/blur) is allowed only for a valid draft.
  bool get canSave => status == SettingsNameStatus.valid;

  String get maskedId => TextConstants.idMask;

  String? get nameError => switch (status) {
    SettingsNameStatus.invalidCharset => TextConstants.usernameCharsetError,
    SettingsNameStatus.taken => TextConstants.nameTakenError,
    _ => null,
  };
}
