part of 'settings_root_bloc.dart';

/// Inline name-edit status (7.1 identity card). Mirrors the 2.3 vocabulary.
/// No `taken`: person labels are not unique (owner, 2026-09-02) and nothing
/// checks them, so the rename field can only be idle, valid or
/// refused on charset.
/// `saveFailed`: the server refused or never answered. The edit stays open on
/// the OLD name, because nothing was saved anywhere and claiming otherwise is
/// what the next greeting would silently undo.
enum SettingsNameStatus { idle, valid, invalidCharset, saveFailed }

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

  /// Save (Enter/Done/blur) is allowed only for a valid draft.
  bool get canSave => status == SettingsNameStatus.valid;

  // Fixed-length, locale-independent id mask (8 U+2022 bullets). Not a localized
  // string, so it stays inline rather than routing through l10n.
  String get maskedId => '••••••••';
}
