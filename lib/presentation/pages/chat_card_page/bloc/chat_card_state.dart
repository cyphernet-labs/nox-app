part of 'chat_card_bloc.dart';

/// Files section view mode (5.4).
enum FilesViewMode { list, grid }

/// Debug-selectable card scenario (5.4, dev-only) — reproduces server-dependent
/// states on stub data (FR-005 / FR-062).
enum ChatCardScenario { normal, empty, offline, fatal }

@freezed
sealed class ChatCardState with _$ChatCardState {
  const ChatCardState._();

  const factory ChatCardState.initializing() = Initializing;

  const factory ChatCardState.initialized({
    required List<MessageAttachment> files,
    @Default(FilesViewMode.list) FilesViewMode viewMode,
    @Default(false) bool isOffline,

    /// Who this machine belongs to, for the People section (5.4).
    ///
    /// Resolved by the BLoC rather than read by the widget: the card owns one,
    /// and a presentation widget reaching for the session repository pays a
    /// keychain round trip on every open for a value the app already holds.
    @Default('') String personLabel,
  }) = Initialized;

  const factory ChatCardState.error() = Error;
}
