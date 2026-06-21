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
  }) = Initialized;

  const factory ChatCardState.error() = Error;
}
