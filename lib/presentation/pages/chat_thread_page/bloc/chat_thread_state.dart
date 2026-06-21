part of 'chat_thread_bloc.dart';

/// Debug-selectable thread scenario (5.2, dev-only) — reproduces the server-dependent
/// states on stub data (FR-005 / FR-029). `sendError` flips the next send to `error`;
/// `offline` keeps sends queued as `pending`.
enum ChatThreadScenario { normal, empty, offline, fatal, sendError }

@freezed
sealed class ChatThreadState with _$ChatThreadState {
  const ChatThreadState._();

  const factory ChatThreadState.initializing() = Initializing;

  const factory ChatThreadState.initialized({
    required PagingState<String, MessageModel> pagingState,
    required String currentId,
    @Default([]) List<MessageModel> items,
    @Default([]) List<MessageModel> outgoing,
    @Default(GetMessagesConfig.defaultPage) int nextPage,
    @Default(false) bool loadingInProgress,
    @Default(false) bool isOffline,
    MessageAttachment? draftAttachment,
  }) = Initialized;

  const factory ChatThreadState.error() = Error;
}

extension ChatThreadInitializedExt on Initialized {
  /// History + optimistic outgoing, oldest → newest (the system line sorts first).
  List<MessageModel> get allMessages {
    final merged = [...items, ...outgoing]..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    return merged;
  }

  /// Real (non-system) messages — drives the Empty state.
  bool get hasMessages => allMessages.any((m) => !m.isSystem);
}
