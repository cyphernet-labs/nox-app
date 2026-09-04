part of 'chats_list_bloc.dart';

/// Debug-selectable load scenario (5.1, dev-only) — reproduces the server-dependent
/// states on stub data (FR-005/FR-053).
/// `unread` is the only scenario that produces a badge through the REAL
/// mechanism: it opens a chat, so a read mark exists, then lets messages
/// arrive above it. Without it no page-level golden contains a chat row with a
/// badge at all, and the desktop rendering of one would have no coverage
/// (Constitution VI).
enum ChatsListScenario { normal, empty, inlineError, fatal, offline, unread }

@freezed
sealed class ChatsListState with _$ChatsListState {
  const ChatsListState._();

  const factory ChatsListState.initializing() = Initializing;

  const factory ChatsListState.initialized({
    required PagingState<String, ChatModel> pagingState,
    @Default([]) List<ChatModel> items,
    @Default(GetChatsConfig.defaultPage) int nextPage,
    // How many pages are currently loaded — the span a live `refresh` re-reads and
    // re-folds (reset→1, load-more→+1, refresh→unchanged).
    @Default(1) int loadedPageCount,
    @Default(false) bool loadingInProgress,
    @Default('') String query,
    @Default(false) bool isOffline,
    @Default(false) bool hasLoadError,
    String? selectedChatId,
  }) = Initialized;

  const factory ChatsListState.error({BaseRepositoryException? exception}) = Error;
}

extension ChatsListInitializedExt on Initialized {
  bool get isSearching => query.trim().isNotEmpty;
}
