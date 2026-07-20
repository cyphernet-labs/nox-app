# Contract: Reactive repository operations

**Feature**: 014-reactive-data-refresh · Phase 1

All operations act on the existing cache-first Sembast DAOs; the network layer stays mocked.

## ChatRepository (domain interface)

```
Future<RepositoryResult<void>> markChatRead({required String chatId});
```

- **Behaviour**: sets the chat's `unreadCount` to 0 in the local DB.
- **No-op guard**: if `unreadCount` is already 0, performs NO write (so it does not emit a redundant
  `watchChats` change or storm the DB).
- **Missing chat**: returns success (nothing to do) — never throws.
- **Reactivity**: a real reset (non-zero → 0) causes `ChatDao.watch()` to emit, refreshing the list badge.

`watchChats()` — unchanged (already streams the cached chats newest-first).

## MessageRepository (domain interface)

```
Stream<List<MessageModel>> watchMessages(String chatId);            // NEW
Future<RepositoryResult<void>> simulateIncoming({required String chatId});  // NEW (debug)
```

- **`watchMessages(chatId)`**: seeds the chat once if empty, then streams that chat's messages
  chronological (oldest→newest) from `MessageDao.watch(chatId)`. Emits on every persisted change.
- **`simulateIncoming(chatId)`** — **must only be invoked under `kDebugMode`** (caller-gated): persists an
  inbound `MessageModel` (`authorId != IdentityMockData.currentUserId`, `status: MessageStatus.none`,
  `sentAt: AppClock.now()`), then updates the parent chat row with `incrementUnread: true`. No automatic /
  periodic generation.

`sendMessage(...)` — unchanged signature; NEW side effect: on the SUCCESS path, after the message is
persisted, it updates the parent chat row (see `_touchChatRow`). A failed send (RepositoryResult.error)
does NOT touch the chat row.

## Data-layer helpers

- **`ChatDao.getById(String id) → Future<ChatEntity?>`**: record-key `get` (no Finder → the
  `field_rename:snake` camelCase gotcha does not apply). Null when absent.
- **`_touchChatRow(chatId, message, {required bool incrementUnread})`** (private, `MessageRepositoryImpl`):
  read the chat via `getById`; if absent, no-op; else `copyWith(lastMessagePreview: chatPreviewFor(message),
  lastMessageAt: message.sentAt.toUtc().toIso8601String(), unreadCount: incrementUnread ? current+1 : current)`
  and upsert. Requires `ChatDao` + `ChatMapper` injected into `MessageRepositoryImpl`.
- **`chatPreviewFor(MessageModel) → String`** (pure util): text → the text; attachment-only →
  `"You: <attachment.name>"`.

## Invariants

1. A message shown in the thread appears exactly once across the pending→persisted transition.
2. The chat row summary (preview/time) always equals the chat's most recent persisted message.
3. `unreadCount` is 0 for a chat whose thread is currently viewed.
4. A failed send changes neither the chat row nor the thread's persisted history.
