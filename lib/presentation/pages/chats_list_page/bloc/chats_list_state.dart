part of 'chats_list_bloc.dart';

/// Debug-selectable load scenario (5.1, dev-only) — reproduces the server-dependent
/// states on stub data (FR-005/FR-053).
/// `unread` is the only scenario that produces a badge through the REAL
/// mechanism: it opens a chat, so a read mark exists, then lets messages
/// arrive above it. Without it no page-level golden contains a chat row with a
/// badge at all, and the desktop rendering of one would have no coverage
/// (Constitution VI).
/// `turnOnTor` stands in for a failed round with a known cause (phase 045):
/// the strip says why instead of «No connection».
enum ChatsListScenario { normal, empty, inlineError, fatal, offline, pinRefused, unread, torObsolete, turnOnTor }

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

    /// The cache had no chats and the server's first page is on its way - the
    /// one wait the list still shows as a spinner.
    @Default(false) bool syncing,
    @Default('') String query,
    @Default(false) bool isOffline,

    /// Something answered at the paired address and it is not this person's
    /// server. Separate from [isOffline] because the two say different things
    /// and lead to different actions: one waits, the other cannot be waited
    /// out.
    @Default(false) bool isServerMismatch,

    /// The server refuses this build for good: «No connection» still shows,
    /// but with nothing to try - a restart of the channel ends the same way
    /// (phase 042).
    @Default(false) bool isUnsupported,

    /// Why there is no connection, when that is known (phase 045): the strip
    /// says it in place of «No connection». Rides with [isOffline] and
    /// [isServerMismatch]; null otherwise.
    ConnectionProblem? problem,

    /// The Tor network has declared the client built into this version
    /// obsolete: the person is asked to update (phase 040, FR-026).
    @Default(false) bool torObsolete,
    @Default(false) bool hasLoadError,
    String? selectedChatId,
  }) = Initialized;

  const factory ChatsListState.error({BaseRepositoryException? exception}) = Error;
}

extension ChatsListInitializedExt on Initialized {
  bool get isSearching => query.trim().isNotEmpty;
}
