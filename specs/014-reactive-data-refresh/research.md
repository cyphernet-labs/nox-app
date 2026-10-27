# Research: Reactive data refresh (mocks)

**Feature**: 014-reactive-data-refresh · **Phase 0** · 2026-07-24

Consolidated from a judge-panel of three reconciliation designs plus focused research on the
send→chat-row update, unread mechanics, and the debug inbound affordance.

---

## R1 — Reconciling reactive `watch` with `infinite_scroll_pagination`

**Decision — "overlay reactive refresh over the existing paged loads" (change-signal + prefix re-fold).**

The chats list and thread keep their proven load path (`getChats`/`getMessages` → `applyPage` →
`PagingState`) as the SINGLE projection of the DB. A `watchChats()` / `watchMessages(chatId)`
subscription is used **only as a change signal** (its emitted value is ignored); each emission
dispatches a `refresh` load that re-reads exactly the currently-loaded page span and re-folds it via
the existing `applyPage`, writing the result onto the LIVE state (no spinner, no scroll reset).

- **Event shape**: widen the existing `LoadChats` / `LoadMessages` event with a `@Default(false) bool
  refresh` flag — refresh MUST ride the SAME `on<...>(..., transformer: sequential())` registration
  as `reset`/load-more, so it cross-serialises (a separate refresh event with its own `sequential()`
  would not serialise against a freshly-appended page → lost-update race).
- **State**: add `@Default(1) int loadedPageCount` to `Initialized` (chats + thread). Everything else
  (`items`, `pagingState`, `nextPage`, `query`, `selectedChatId`, `isOffline`, `hasLoadError`,
  `loadingInProgress`) is unchanged.
- **Refresh branch** (before the `loadingInProgress` guard; does NOT set `loadingInProgress`/`isLoading`
  → invisible): re-query pages `defaultPage .. defaultPage+loadedPageCount-1` from the repo, fold from a
  clean `PagingState()` + empty accumulator, then `emit(live.copyWith(items, pagingState, nextPage))`.
  MUST: (a) stale-guard — re-read state after each `await`, abort if `query` changed; (b) swallow repo
  errors and keep the current list (a background refresh must never blank the screen or raise a
  full-screen `Error`); (c) early-return for the `fatal`/`empty` debug scenarios so their stubbed states
  aren't overwritten.
- **`loadedPageCount` lockstep**: `reset`→1, load-more→`current+1`, `refresh`→unchanged.

**Rationale** (winning axes): smallest blast radius (`getChats`/`getMessages`, `applyPage`,
`sequential()`, `PagedListView` binding, load-more and scenarios all stay byte-for-byte — the change
is additive: a subscription + a flag + a counter); keeps blueprint 07's network-only server-paginated
carve-out intact (`PagingState` stays real, load-more stays real); and is the ONLY option genuinely
backend-compatible — "re-query the loaded prefix on a change signal" is exactly what a real cache-first
+ server-pagination client does (at backend time `getChats` hits the server and `watchChats()` becomes
a change-stream over the locally-cached loaded pages; only the overlay is revisited).

**Alternatives rejected:**
- **A — "watch is the source of truth, paging is a projected window"** (hold the full ordered list in
  the bloc, project a window): elegant and trivially unit-testable, but introduces a SECOND Dart-side
  projection (in-bloc `name.contains` search + windowing) that must be kept behaviourally identical to
  the repo's trim+lowercase search (latent divergence), turns `getChats`/`getMessages` into dead paths
  (drift-rot), and requires the full ordered list streamable to the client — a real re-architecture
  when the server owns pagination.
- **C — "collapse paging to a reactive in-memory list"** (single full page, `PagingState` demoted):
  worst backend cost (must re-introduce true paging AND then still solve the reactive+paged
  reconciliation, PLUS migrate off full-in-memory), abandons the 07 carve-out for the exact surface
  most likely to grow unbounded (open space, all chats, never deleted), and forces a blueprint
  amendment + golden regeneration now.

**Grafted from A/C**: `_threadPane` resolves the selected `ChatModel` with an empty-pane fallback when
an active search filters it out (A's robustness note) on top of D2's `state.items`-based resolution.

---

## R2 — `sendMessage` updates the parent chat row (FR-001/002/003/004)

**Decision.** In `MessageRepositoryImpl.sendMessage`, on the SUCCESS path only and AFTER the message
`upsert`, call a private `_touchChatRow(chatId, persistedMessage, incrementUnread: false)`. Inject
`ChatDao` + `ChatMapper` into `MessageRepositoryImpl` (a data→data dependency). `_touchChatRow` reads
the `ChatEntity` (new `ChatDao.getById(id)` via `_store.record(id).get(db)` — a record-key lookup, so
the global `field_rename:snake` camelCase-Finder gotcha does NOT apply), `copyWith`s
`lastMessagePreview: chatPreviewFor(message)`, `lastMessageAt: message.sentAt.toUtc().toIso8601String()`,
`unreadCount: incrementUnread ? current+1 : current`, and upserts.

Because `ChatDao.watch()` backs the reactive list (R1), the preview/time/newest-first reorder propagate
live with **zero chat-list-bloc awareness** — no bloc-to-bloc coupling.

- **`chatPreviewFor`** (pure util): text → the text; attachment-only → `"You: <attachment.name>"` (per
  the clarification — filename with author prefix, no new l10n string, no emoji).
- **FR-004 (failed send)** falls out of ORDERING: a failed send returns `RepositoryResult.error` before
  the `upsert`, so the row is never touched; the debug offline/sendError paths short-circuit in
  `_deliver` before `sendMessage` is called.

**Rationale**: keeps the update in the data layer where the write already happens, minimal coupling
(one injected DAO), guaranteed-by-construction failure semantics.

**Alternatives**: a coordinating call in the bloc (rejected — bloc-to-bloc coupling, presentation owns
data consistency); `ChatRepository.touchChat(...)` called from the message path (rejected — extra
indirection; the message repo already holds the write transaction boundary).

**Risk**: the hardcoded `"You:"` prefix is stored in the DB (no l10n at the data layer) — matches the
clarification literal but is untranslated-in-DB debt; flagged, acceptable for this phase.

---

## R3 — Unread mechanics (FR-009/FR-010)

**Decision.**
- **Reset**: `ChatRepository.markChatRead(chatId)` = read-modify-write `unreadCount: 0`, **no-op when
  already 0** (avoids a write storm / redundant `watchChats` emission). Called from the thread bloc's
  `_onInitialize` — a single seam that covers BOTH mobile push (a fresh thread route) AND desktop
  select (selecting rebuilds a fresh keyed thread bloc); merely rendering a list row builds no thread
  bloc, so it is correctly NOT a read.
- **"Inbound to the currently-viewed chat stays read"** falls out for free by re-calling `markChatRead`
  on every message-updated refresh tick in the open thread — no shared mutable "currently-viewed"
  registry to keep in sync or reset on logout/close.
- **Increment**: only via the debug `simulateIncoming` path (R4), `incrementUnread: true`.
- **Own send never bumps unread** (`_touchChatRow(..., incrementUnread: false)`).

**Rationale**: per-tick `markChatRead` in the open thread is simpler and safer than a `ViewedChatRegistry`
singleton (no cross-cutting mutable state); the no-op-at-0 guard prevents write amplification.

**Alternative rejected**: a `ViewedChatRegistry` singleton holding `activeChatId` (from design A) — works
but adds shared mutable state that must be cleared on logout/dispose and reset in tests.

**Risk**: a debug inbound into the currently-viewed chat can transiently show a phantom badge
(increment then reset are two separate Sembast writes); it self-heals on the next tick — acceptable for
a debug-only affordance.

---

## R4 — Debug "Simulate incoming" affordance (FR-010)

**Decision.** `MessageRepository.simulateIncoming({required String chatId})`, **`kDebugMode`-gated at the
call site**, upserts an inbound `MessageModel` (author != `me`, `status: none`, `sentAt: AppClock.now()`)
into `MessageDao`, then `_touchChatRow(chatId, message, incrementUnread: true)`. The control lives in the
existing debug surfaces — the chat-thread `ChatThreadScenario` dropdown gains a "Simulate incoming" action
(and/or a chats-list debug control), mirroring the established `kDebugMode && demo` scenario pattern, so it
never ships to users or goldens.

**Testability**: deterministic under a frozen `AppClock`; a bloc/widget test drives `simulateIncoming`
directly and asserts the thread appends the message (in the open chat) or the list badge increments (in a
non-viewed chat).

**Rationale**: reuses the message write path + `_touchChatRow`; matches the clarification (debug-only, no
auto/periodic generation).

**Alternative rejected**: an automatic periodic/random generator (non-deterministic, breaks goldens/tests,
rejected in clarify).

---

## Cross-cutting risks / verification (carried into tasks)

1. `loadedPageCount` must stay in lockstep; `refresh` must remain a FLAG on the existing handler (same
   `sequential()`).
2. The refresh branch must swallow repo errors and stale-guard on `query` after every `await`.
3. Debounce each `watch` subscription (coalesce write bursts) and collapse the initial seed emission so
   `watch()` + the seeding `getChats`/`getMessages` don't fire a redundant init-time refresh. Correctness
   holds without the debounce (`sequential()` serialises), but it prevents a refresh storm.
4. **Verify** `AppThreadViewWidget` uses a persistent `ScrollController` + `ValueKey(message.id)` rows — a
   live refresh must not jump the scroll offset (currently unverified).
5. `getMessages`/`watchMessages` both call `_seedChatIfEmpty` — idempotent (upsert-by-id) but a redundant
   double seed; ensure the seed emission is collapsed.
6. Thread no-double-bubble requires the persisted own message to carry `status: sent` (SendMessageApi
   already returns `sent`).
