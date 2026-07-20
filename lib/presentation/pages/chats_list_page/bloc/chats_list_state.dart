part of 'chats_list_bloc.dart';

/// Debug-selectable load scenario (5.1, dev-only) — reproduces the server-dependent
/// states on stub data (FR-005/FR-053).
enum ChatsListScenario { normal, empty, inlineError, fatal, offline }

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
