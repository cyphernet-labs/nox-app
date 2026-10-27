# Contract: BLoC event/state deltas + reactive refresh

**Feature**: 014-reactive-data-refresh · Phase 1

## ChatsListBloc (5.1)

**Event**: `LoadChats` widened →

```
const factory ChatsListEvent.loadChats({@Default(false) bool reset, @Default(false) bool refresh}) = LoadChats;
```

- `refresh` is handled on the SAME `on<LoadChats>(_onLoadChats, transformer: sequential())` registration
  (never a separate event/transformer — cross-serialisation with reset/load-more is required).

**State (`Initialized`)**: `+ @Default(1) int loadedPageCount`.

**Subscription**: `_chatsSub = chatRepository.watchChats().listen((_) => add(const ChatsListEvent.loadChats(refresh: true)))`
started after the initial `reset` load in `_onInitialize`; cancelled in `close()`. The emitted value is
ignored (change signal only).

**Refresh contract** (`refresh == true`, evaluated BEFORE the `loadingInProgress` guard):
1. Skip if the debug scenario is `fatal` or `empty` (do not overwrite their stubbed states).
2. Do NOT set `loadingInProgress`/`isLoading` (invisible, no spinner).
3. Re-query pages `defaultPage .. defaultPage + loadedPageCount - 1` via `getChats(nextPage(page, search))`,
   folding through `applyPage` from a clean `PagingState()` + empty accumulator.
4. After every `await`, re-read state; ABORT if `query` changed (a newer `SearchChanged` supersedes).
5. On a repo error mid-refresh: ABORT, keep the current list (never blank the screen / raise `Error`).
6. `emit(live.copyWith(items: acc, pagingState: folded, nextPage: lastNext ?? live.nextPage))` — onto the
   LIVE state so `query`/`selectedChatId`/`isOffline`/`hasLoadError`/`loadedPageCount`/`loadingInProgress`
   carry through untouched.

**`loadedPageCount`**: 1 on `reset` success; `+1` on load-more success; unchanged on `refresh`.

**Page (`chats_list_page.dart`)**: `_threadPane` resolves the selected `ChatModel` from `state.items`; when
an active search filters the selection out, it renders the illustrated empty pane (no stale thread).
Unchanged: `_scrollController`, `ValueKey(chat.id)` rows, `PagedListView.state`/`fetchNextPage` binding.

**Acceptance (bloc_test)**: after seeding + a DAO write (createChat / sendMessage / simulateIncoming), a
`refresh` tick leaves `loadedPageCount` unchanged, preserves `query`/`selectedChatId`, and updates
`items` ordering/preview/unread.

## ChatThreadBloc (5.2)

**Event**: `LoadMessages` widened → `loadMessages({reset, refresh})` on the same `sequential()` handler.

**State (`Initialized`)**: `+ @Default(1) int loadedPageCount`; `allMessages` getter → **dedup-by-id**
(outgoing entries whose id is already in `items` are dropped; concat; sort by `sentAt`).

**Subscription**: `_msgSub = messageRepository.watchMessages(chatId).listen((_) => add(const ChatThreadEvent.loadMessages(refresh: true)))`
in `_onInitialize`; `chatRepository.markChatRead(chatId)` called in `_onInitialize` AND on each refresh
tick; `_msgSub` cancelled in `close()`.

**Refresh contract**: re-query pages `1..loadedPageCount` via `getMessages`, re-fold `items` via
`applyPage`, WITHOUT touching `outgoing`/`draftAttachment`/`loadingInProgress`.

**No double bubble** (FR-007/SC-003): in `_deliver` success, REPLACE the `outgoing` entry with the
persisted `MessageModel` (`srv_<uuid>` id, `status: sent`). Error keeps `local_<n>` for `SendRetried`.

**Acceptance (bloc_test)**: sending a message yields exactly one bubble across pending→sent (id adoption +
dedup); a `simulateIncoming` for the open chat appears in `allMessages` in chronological order; older-history
scroll-up paging still works.

## Cross-screen invariants (widget-level)

- Mobile: create → list shows the new chat (via `openCreated` reload, already shipped) AND thereafter a
  send in any chat live-updates its row.
- Desktop: selecting a chat marks it read (badge → 0) and shows the thread in the pane; a send updates the
  selected chat's row + pane together; selection is retained across a refresh.
