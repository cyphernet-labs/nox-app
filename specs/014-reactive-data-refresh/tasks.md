---
description: "Task list for 014 reactive data refresh"
---

# Tasks: Reactive data refresh (mocks)

**Input**: Design documents from `specs/014-reactive-data-refresh/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: included (project convention — every feature ships bloc_test/repo/widget coverage; see
CLAUDE.md *Testing* and quickstart.md).

## Format: `[ID] [P?] [Story] Description with file path`

- **[P]**: parallelizable (different files, no dependency on an incomplete task)
- **[Story]**: US1–US4 from spec.md (Setup/Foundational/Polish have no story label)

---

## Phase 1: Setup

- [ ] T001 Decide the watch-subscription debounce approach (reuse `debounceRestartable`/rxdart already in
  `lib/presentation/base/bloc_transformers.dart`, or a small `Timer`) and how to collapse the initial
  seed emission; no new pubspec dep expected. Record the choice as a comment at the two subscription
  sites. File: `lib/presentation/base/bloc_transformers.dart` (reference only).

---

## Phase 2: Foundational (shared data helpers — used by US2 and US4)

- [ ] T002 [P] Add `Future<ChatEntity?> getById(String id)` (record-key `_store.record(id).get(db)`) to
  `lib/data/local/chat/chat_dao.dart`.
- [ ] T003 [P] Add pure util `String chatPreviewFor(MessageModel m)` (text → text; attachment-only →
  `"You: <attachment.name>"`) in `lib/general/formatters/chat_preview_formatter.dart`.
- [ ] T004 [P] Test `ChatDao.getById` (hit + miss) in `test/data/local/chat/chat_dao_test.dart`.
- [ ] T005 [P] Test `chatPreviewFor` (text vs attachment-only) in
  `test/general/formatters/chat_preview_formatter_test.dart`.

**Checkpoint**: helpers exist + green; US1 can proceed in parallel (it does not depend on these).

---

## Phase 3: User Story 1 — Chats list stays current (Priority: P1) 🎯 MVP

**Goal**: the chats list live-updates from the DB (new chat, sent-message preview/order/unread) without a
manual refresh, on mobile and desktop.

**Independent test**: seed the list; drive a DAO write (create/send); a refresh tick updates
ordering/preview and preserves scroll, loaded pages, search and desktop selection.

- [ ] T006 [US1] Widen `ChatsListEvent.loadChats` with `@Default(false) bool refresh` and add
  `@Default(1) int loadedPageCount` to `Initialized` in
  `lib/presentation/pages/chats_list_page/bloc/chats_list_event.dart` +
  `lib/presentation/pages/chats_list_page/bloc/chats_list_state.dart`.
- [ ] T007 [US1] Implement the refresh branch in `_onLoadChats` (re-query pages
  `1..loadedPageCount` via `getChats`, fold from a clean `PagingState()` via `applyPage`, stale-guard on
  `query` after each await, swallow repo errors keeping the current list, skip the `fatal`/`empty`
  scenarios, do NOT set `loadingInProgress`) + `loadedPageCount` lockstep (reset→1, load-more→+1,
  refresh→unchanged) in `lib/presentation/pages/chats_list_page/bloc/chats_list_bloc.dart`.
- [ ] T008 [US1] Subscribe to `chatRepository.watchChats()` in `_onInitialize` (debounced change-signal →
  `add(loadChats(refresh: true))`, value ignored); cancel `_chatsSub` in `close()` in
  `lib/presentation/pages/chats_list_page/bloc/chats_list_bloc.dart`.
- [ ] T009 [US1] `_threadPane` resolves the selected `ChatModel` from `state.items` with an empty-pane
  fallback when an active search filters it out, in
  `lib/presentation/pages/chats_list_page/chats_list_page.dart`.
- [ ] T010 [P] [US1] bloc_test: a DAO write drives a refresh tick that preserves
  `loadedPageCount`/`query`/`selectedChatId` and updates `items` ordering/preview/unread; load page-2 then
  refresh keeps both pages, in
  `test/presentation/pages/chats_list_page/bloc/chats_list_bloc_test.dart`.
- [ ] T011 [US1] Regenerate the 5.1 goldens ONLY if reactive ordering changes the rendered surface (run
  `make golden-verify`; `make golden-update FILE=…` if it legitimately changed) under
  `test/presentation/pages/chats_list_page/goldens/`.

**Checkpoint**: US1 independently testable + gate green.

---

## Phase 4: User Story 2 — Sent message keeps list and thread consistent (Priority: P1)

**Goal**: `sendMessage` updates the parent chat row (preview/time/reorder) in the DB. Depends on Phase 2
(getById, chatPreviewFor).

**Independent test**: a repo test — send updates the row; a failed send leaves it untouched.

- [ ] T012 [US2] Inject `ChatDao` + `ChatMapper` into `MessageRepositoryImpl` and add private
  `_touchChatRow(String chatId, MessageModel message, {required bool incrementUnread})` (getById →
  copyWith preview/`lastMessageAt`/unread → upsert) in
  `lib/data/repository/chat/message_repository_impl.dart` (regenerate DI).
- [ ] T013 [US2] Call `_touchChatRow(chatId, persisted, incrementUnread: false)` on the `sendMessage`
  SUCCESS path AFTER the message upsert (failed send returns error earlier → row untouched, FR-004) in
  `lib/data/repository/chat/message_repository_impl.dart`.
- [ ] T014 [P] [US2] repo test: send sets the chat row preview (text, or `"You: <name>"` for an
  attachment) + `lastMessageAt` + reorder; a failed send leaves the row untouched; own send does not bump
  unread, in `test/data/repository/chat/message_repository_impl_test.dart`.

**Checkpoint**: send→row locked; combined with US1, sending live-updates the list.

---

## Phase 5: User Story 3 — Open thread updates live (Priority: P2)

**Goal**: the open thread live-updates from `watchMessages` while preserving the optimistic send and
older-history paging.

**Independent test**: bloc_test — a persisted new message appears in `allMessages` in order; own send
shows exactly one bubble across pending→sent.

- [ ] T015 [US3] Add `Stream<List<MessageModel>> watchMessages(String chatId)` to
  `lib/domain/repository/chat/message_repository.dart` and implement it (seed-then-
  `_messageDao.watch(chatId).map(toModel)`) in `lib/data/repository/chat/message_repository_impl.dart`.
- [ ] T016 [US3] Widen `ChatThreadEvent.loadMessages` with `refresh`, add `@Default(1) int loadedPageCount`
  to `Initialized`, and change the `allMessages` getter to dedup-by-id in
  `lib/presentation/pages/chat_thread_page/bloc/chat_thread_event.dart` +
  `lib/presentation/pages/chat_thread_page/bloc/chat_thread_state.dart`.
- [ ] T017 [US3] Implement the thread refresh branch (re-query pages `1..loadedPageCount` via
  `getMessages`, re-fold `items` via `applyPage`, do NOT touch `outgoing`/`draftAttachment`/
  `loadingInProgress`) + subscribe to `watchMessages(_chatId)` (debounced) in `_onInitialize` + cancel in
  `close()`, in `lib/presentation/pages/chat_thread_page/bloc/chat_thread_bloc.dart`.
- [ ] T018 [US3] In `_deliver` success, adopt the server id — replace the optimistic `outgoing` entry with
  the persisted `MessageModel` (`srv_<uuid>` id, `status: sent`) so the watch tick's copy is deduped by id
  (exactly one bubble), in `lib/presentation/pages/chat_thread_page/bloc/chat_thread_bloc.dart`.
- [ ] T019 [US3] Verify `AppThreadViewWidget` uses a persistent `ScrollController` + `ValueKey(message.id)`
  rows so a live refresh does not jump the scroll offset (fix if not) in
  `lib/presentation/widgets/chat/app_thread_view_widget.dart`.
- [ ] T020 [P] [US3] bloc_test: exactly one bubble across pending→sent (id adoption + dedup); a persisted
  new message appears in chronological order; older-history scroll-up paging still works, in
  `test/presentation/pages/chat_thread_page/bloc/chat_thread_bloc_test.dart`.

**Checkpoint**: thread live-updates without double bubbles.

---

## Phase 6: User Story 4 — Unread badges reflect reading (Priority: P3)

**Goal**: reset unread on view; increment via a debug inbound. Depends on Phase 2 + US2 (`_touchChatRow`)
+ US3 (thread bloc subscription).

**Independent test**: repo test (markChatRead / simulateIncoming) + a bloc/widget test.

- [ ] T021 [US4] Add `Future<RepositoryResult<void>> markChatRead({required String chatId})` to
  `lib/domain/repository/chat/chat_repository.dart` and implement it (read-modify-write `unreadCount: 0`,
  no-op when already 0) in `lib/data/repository/chat/chat_repository_impl.dart`.
- [ ] T022 [US4] Call `chatRepository.markChatRead(chatId)` in the thread bloc `_onInitialize` AND on each
  refresh tick in `lib/presentation/pages/chat_thread_page/bloc/chat_thread_bloc.dart`.
- [ ] T023 [US4] Add `Future<RepositoryResult<void>> simulateIncoming({required String chatId})` to
  `lib/domain/repository/chat/message_repository.dart` + impl (upsert inbound `authorId != me`, `status:
  none`, `sentAt: AppClock.now()`, then `_touchChatRow(..., incrementUnread: true)`) in
  `lib/data/repository/chat/message_repository_impl.dart`.
- [ ] T024 [US4] Add a `kDebugMode`-gated "Simulate incoming" control on the **chats-list** debug surface
  that targets a chat OTHER than the currently-selected/open one, wired to
  `messageRepository.simulateIncoming(chatId)`, in `lib/presentation/pages/chats_list_page/chats_list_page.dart`.
  RATIONALE (analyze F1): a control only in the OPEN thread would land in the viewed chat and be reset
  immediately by `markChatRead` (FR-009), so the FR-010 increment would never be observable in the UI — the
  increment path MUST be exercisable against a NON-viewed chat. A thread-side "simulate into this chat"
  action may ADDITIONALLY exist for the live-thread demo (US3), but is not sufficient for FR-010.
- [ ] T025 [P] [US4] repo test: `markChatRead` resets to 0 and is a no-op at 0; `simulateIncoming`
  increments unread + appends the inbound, in `test/data/repository/chat/chat_repository_impl_test.dart` +
  `test/data/repository/chat/message_repository_impl_test.dart`.
- [ ] T026 [P] [US4] bloc/widget test: opening a thread fires `markChatRead` (badge → 0); `simulateIncoming`
  for a non-viewed chat increments the list badge (99+ cap honoured), in
  `test/presentation/pages/chat_thread_page/bloc/chat_thread_bloc_test.dart`.

**Checkpoint**: unread resets on view + increments on debug inbound, live in the list.

---

## Phase 7: Polish & Cross-Cutting

- [ ] T027 Debounce the two `watch` subscriptions and collapse the initial seed emission so
  `watch()` + the seeding load don't fire a redundant init-time refresh (risk #3) in
  `lib/presentation/pages/chats_list_page/bloc/chats_list_bloc.dart` +
  `lib/presentation/pages/chat_thread_page/bloc/chat_thread_bloc.dart`.
- [ ] T028 Blueprint drift-fix (Constitution II): note that `watch()` is a change-signal over the
  cache-first store driving a re-read of the loaded prefix, in `docs/blueprints/mobile/04-*.md` +
  `docs/blueprints/mobile/07-pagination.md`.
- [ ] T029 Run `make gate` + `make golden-verify` green; after merging 014 into `develop`, tick R1/R2/R3/D2
  in `docs/mock-completion-plan.md` (§2 tracker + §6 journal).
- [ ] T030 Desktop parity widget test (`_wide` list-detail) — analyze C1 / FR-011 / SC-006: a send /
  `simulateIncoming` updates the selected chat's row AND its detail pane together with the selection
  retained across the refresh, and a non-viewed chat's list badge increments live, in
  `test/presentation/pages/chats_list_page/chats_list_page_test.dart` (or a dedicated `_wide` reactive
  test). Runs after US1–US4 (cross-cutting; the bloc tests T010/T020/T026 are layout-agnostic).

---

## Analyze remediation (2026-07-24, read-only /speckit-analyze)

- **F1 (MEDIUM) fixed** — T024 pins the debug "Simulate incoming" control to the chats-list surface
  targeting a NON-viewed chat, so the FR-010 unread increment is observable (a thread-only control lands
  in the viewed chat and self-resets).
- **C1 (MEDIUM) fixed** — T030 adds explicit `_wide` desktop parity coverage (FR-011/SC-006); the
  per-story bloc tests are layout-agnostic.
- **U1 (LOW), accepted** — SC-001 (<1 s) is verified via the quickstart manual step; no build task
  (reactivity is by design, not measurable infra).
- **L1 (LOW), accepted** — the stored `"You:"` attachment-preview prefix is a data-layer literal per the
  clarification (EN microcopy; untranslated-in-DB debt), documented in plan.md/research.md.
- **I1 (LOW), accepted** — the 5.2 (thread) golden is absent (removed earlier; tracked as E1 in
  `docs/mock-completion-plan.md`); the thread is covered here by bloc/widget tests (T020/T026/T030).

---

## Dependencies & execution order

- **Setup (T001)** → everything.
- **Foundational (T002–T005)** → US2 + US4 (getById, chatPreviewFor). NOT required by US1.
- **US1 (T006–T011)** — independent; can start right after Setup. **MVP with US2.**
- **US2 (T012–T014)** — needs Foundational.
- **US3 (T015–T020)** — independent of US1/US2 (own `watchMessages`); needs its own bloc only.
- **US4 (T021–T026)** — needs US2 (`_touchChatRow`) + US3 (thread bloc subscription seam).
- **Polish (T027–T030)** — after the stories. T030 (desktop parity widget test) runs LAST — it needs
  US1–US4 done.

**Within a bloc file, tasks are sequential** (T007→T008, T016→T017→T018, T022 on the thread bloc).

## Parallel opportunities

- Foundational: T002, T003, T004, T005 all `[P]` (distinct files).
- Tests across stories: T010, T014, T020, T025, T026 `[P]` (distinct test files).
- US1 and US3 blocs can be built in parallel (different bloc files).

## Implementation strategy

- **MVP = US1 + US2** (the P1 pair): the list live-updates and a send updates its row → delivers the
  headline "data refreshes when it changes". Ship/verify, then add US3 (live thread) and US4 (unread).
- After each Freezed event/state change (T006, T016) run `make generate` (the gate does this) before
  testing.
- Keep each user story a green `make gate` increment; commit per story (US1, US2, US3, US4, polish) on the
  `014` branch, then merge to `develop` (no push).
