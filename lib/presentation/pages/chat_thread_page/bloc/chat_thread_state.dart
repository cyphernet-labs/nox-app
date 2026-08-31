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
    // The oldest loaded journal number - the before_seq cursor of the next
    // older batch; null until the first tail load lands.
    int? oldestLoadedSeq,
    @Default(false) bool loadingInProgress,
    @Default(false) bool isOffline,
    MessageAttachment? draftAttachment,
  }) = Initialized;

  const factory ChatThreadState.error() = Error;
}

extension ChatThreadInitializedExt on Initialized {
  /// History + optimistic outgoing, ascending by the journal seq (the genesis
  /// line owns the chat's lowest seq; optimistic sends carry [kPendingSeq]
  /// and stay at the newest end until acked). Dedup-by-id (Feature 014):
  /// once an optimistic send is acked it adopts the persisted `srv_<uuid>`
  /// id, and the live `items` also carry it — keep only one bubble.
  List<MessageModel> get allMessages {
    final itemIds = items.map((m) => m.id).toSet();
    final queueIndex = <String, int>{for (var i = 0; i < outgoing.length; i++) outgoing[i].id: i};
    final merged = [...items, ...outgoing.where((m) => !itemIds.contains(m.id))]
      ..sort((a, b) {
        final bySeq = a.seq.compareTo(b.seq);
        if (bySeq != 0) return bySeq;
        final byTime = a.sentAt.compareTo(b.sentAt);
        if (byTime != 0) return byTime;
        // Queued sends share the sentinel seq AND (under a frozen clock) the
        // timestamp: their tiebreak is the queue position. Comparing ids would
        // order them by a uuid, i.e. at random — the one thing send order must
        // never be.
        final byQueue = (queueIndex[a.id] ?? -1).compareTo(queueIndex[b.id] ?? -1);
        return byQueue != 0 ? byQueue : a.id.compareTo(b.id);
      });
    return merged;
  }

  /// Real (non-system) messages — drives the Empty state.
  bool get hasMessages => allMessages.any((m) => !m.isSystem);
}
