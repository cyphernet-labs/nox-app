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
    // The person's own server-minted id, shown whole in the 7.1 identity card and
    // handed to `Copy ID`. Loaded from the session on initialize; absent or
    // unreadable degrades to '' - never to a stand-in, because a fabricated id
    // would be copied out as if it were real.
    @Default('') String rawId,

    @Default('') String draftName,
    @Default(false) bool editing,
    @Default(SettingsNameStatus.idle) SettingsNameStatus status,
  }) = _SettingsRootState;

  /// Save (Enter/Done/blur) is allowed only for a valid draft.
  bool get canSave => status == SettingsNameStatus.valid;
}
