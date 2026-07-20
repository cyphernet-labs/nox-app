# Data Model: Reactive data refresh (mocks)

**Feature**: 014-reactive-data-refresh · **Phase 1** · 2026-07-24

No new persisted entities — existing `ChatEntity`/`MessageEntity` (Sembast) and `ChatModel`/`MessageModel`
(domain) already carry every needed field. This feature adds **operations** on the existing data layer
and **state/event deltas** on the two BLoCs.

## Entities (unchanged shape)

- **Chat** (`ChatModel` / `ChatEntity`): `id`, `name`, `lastMessagePreview`, `lastMessageAt` (DateTime /
  ISO), `unreadCount`. Ordered newest-first by `lastMessageAt` (`ChatDao` sorts in Dart). Never deleted
  (open-space model).
- **Message** (`MessageModel` / `MessageEntity`): `id`, `chatId`, `authorId`, `authorLabel`, `text?`,
  `sentAt`, `status` (`none`/`pending`/`sent`/`error`), `isSystem`, flattened `attachment*`. Belongs to
  one Chat.
- **Unread count**: the `Chat.unreadCount` field. Increases on a (debug) inbound to a non-viewed chat;
  resets to 0 when the chat's thread is viewed.

## New / changed data-layer operations

| Layer | Operation | Contract |
|---|---|---|
| `ChatDao` | `Future<ChatEntity?> getById(String id)` | Record-key `get` (`_store.record(id).get(db)`). Record-key lookup — the `field_rename:snake` Finder gotcha does NOT apply. Returns null if absent. |
| `ChatRepository` | `Future<RepositoryResult<void>> markChatRead({required String chatId})` | Read-modify-write `unreadCount: 0`. **No-op when already 0** (no write, no redundant `watch` emission). |
| `MessageRepository` | `Stream<List<MessageModel>> watchMessages(String chatId)` | Mirrors `watchChats`: `await _seedChatIfEmpty(chatId); yield* _messageDao.watch(chatId).map(toModel)`. Chronological (oldest→newest). |
| `MessageRepository` | `Future<RepositoryResult<void>> simulateIncoming({required String chatId})` | **Debug/`kDebugMode`-gated at the call site.** Upserts an inbound `MessageModel` (`authorId != me`, `status: none`, `sentAt: AppClock.now()`), then `_touchChatRow(chatId, msg, incrementUnread: true)`. |
| `MessageRepositoryImpl` (private) | `_touchChatRow(chatId, message, {required bool incrementUnread})` | After a successful message upsert: read `ChatDao.getById`, `copyWith(lastMessagePreview: chatPreviewFor(message), lastMessageAt: message.sentAt.toUtc().toIso8601String(), unreadCount: incrementUnread ? current+1 : current)`, upsert. Requires injecting `ChatDao` + `ChatMapper` into `MessageRepositoryImpl` (data→data). |
| `general/formatters/chat_preview_formatter.dart` | `String chatPreviewFor(MessageModel)` (pure util) | `text` non-empty → the text; attachment-only → `"You: <attachment.name>"` (author prefix + filename; no new l10n string, no emoji). |

**Ordering guarantees FR-004**: `sendMessage` calls `_touchChatRow` ONLY on the success path, AFTER the
message upsert; a failed send returns `RepositoryResult.error` earlier, so the chat row is never touched.

## BLoC state / event deltas

### ChatsListBloc (5.1)

- **State (`Initialized`)**: add `@Default(1) int loadedPageCount`. Everything else unchanged.
- **Event**: widen `LoadChats` → `loadChats({@Default(false) bool reset, @Default(false) bool refresh})`.
  No new event type — `refresh` rides the SAME `on<LoadChats>(..., transformer: sequential())`.
- **Subscription**: `_chatsSub = _chatRepository.watchChats().listen((_) => add(loadChats(refresh: true)))`,
  started in `_onInitialize` (after the initial `reset` load), cancelled in `close()`. Value ignored.
- **Refresh handler branch**: re-query pages `1..loadedPageCount`, re-fold via `applyPage` from a clean
  `PagingState()`, emit onto the LIVE state (no `loadingInProgress`/`isLoading`); stale-guard on `query`;
  swallow errors; skip when scenario is `fatal`/`empty`.
- **`loadedPageCount`**: `reset`→1, load-more→+1, `refresh`→unchanged.

### ChatThreadBloc (5.2)

- **State (`Initialized`)**: add `@Default(1) int loadedPageCount`. Change the `allMessages` computed
  getter to **dedup-by-id**: keep every `outgoing` entry whose id is not already in `items`, concat with
  `items`, sort by `sentAt`.
- **Event**: widen `LoadMessages` → `loadMessages({reset, refresh})` on the same `sequential()` handler.
- **Subscription**: `_msgSub = _messageRepository.watchMessages(_chatId).listen((_) => add(loadMessages(refresh: true)))`
  in `_onInitialize`; also call `_chatRepository.markChatRead(chatId)` there and on each refresh tick;
  cancel in `close()`.
- **No double bubble** (FR-007/SC-003): in `_deliver` success, REPLACE the optimistic `outgoing` entry
  with the persisted `MessageModel` (its `srv_<uuid>` id + `status: sent`), so the watch tick's copy is
  deduped by id → exactly one bubble. Error keeps `local_<n>` (retryable).
- Older-history paging (`reset:false` scroll-up), `draftAttachment`, offline queue: unchanged.

## State transitions

- **Unread**: `>0 --(view thread: markChatRead)--> 0`; `0 --(debug inbound, non-viewed)--> +1`; inbound
  to the viewed chat: `0 --(increment then per-tick markChatRead)--> 0` (transient badge self-heals).
- **Message status** (unchanged): `pending --(ack)--> sent` (via id adoption) or `pending --(fail)--> error --(retry)--> pending`.
