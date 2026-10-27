# Implementation Plan: Reactive data refresh (mocks)

**Branch**: `014-reactive-data-refresh` | **Date**: 2026-07-24 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/014-reactive-data-refresh/spec.md`

## Summary

Make the chats list (5.1) and chat thread (5.2) live-update from the local Sembast DB, and keep the
list and thread consistent when a message is sent — all on the existing cache-first mock repositories,
network layer still mocked. Chosen approach (see [research.md](research.md) R1): the reactive
`watchChats()` / new `watchMessages(chatId)` streams are used as a **change signal** that dispatches a
`refresh` load; the existing `getChats`/`getMessages` + `applyPage` + `PagingState` remain the single
projection path (smallest blast radius, keeps blueprint-07 paging intact, backend-compatible).
`sendMessage` updates the parent chat row in the DB (preview/time/reorder) so the reactive list reflects
it with no bloc-to-bloc coupling; unread resets when a thread is viewed and increments only via a
`kDebugMode` "Simulate incoming" affordance.

## Technical Context

**Language/Version**: Dart >=3.12, Flutter 3.44.1 (FVM-pinned)

**Primary Dependencies**: flutter_bloc + freezed (Freezed BLoC), injectable + get_it (DI),
infinite_scroll_pagination v5 (`PagingState`), sembast (local DB), bloc_concurrency (`sequential()`)

**Storage**: local **Sembast** DB (cache-first per blueprint 04/07) — `ChatDao` / `MessageDao`; no
backend / network transport (mocked)

**Testing**: `flutter test` (bloc_test + widget), mockito-only, deep-mirrored under `test/`; goldens via
`goldenTest`/`goldenTestDesktop` (both categories), macOS-only, excluded from `make test`

**Target Platform**: iOS, Android, macOS, Windows, Linux (one Flutter codebase; `_narrow`/`_wide`)

**Project Type**: mobile+desktop app (single Dart package `nox_app`, Clean Architecture layers)

**Performance Goals**: reactive updates reflected in < 1s (SC-001); 60 fps list/thread; no scroll jump on
a live refresh

**Constraints**: mocks only (no backend); reactive refresh must not reset scroll, discard loaded pages,
lose the active search, or drop desktop selection; message shown exactly once across pending→persisted;
mobile (`_narrow`) + desktop (`_wide` list-detail) parity

**Scale/Scope**: mock set ~28 chats (pageSize 20 → 2 pages), ~14 messages/thread (< 1 page); 2 BLoCs +
2 repositories + 2 DAOs touched, plus a debug affordance

## Constitution Check

*GATE: must pass before Phase 0 (passed) and re-checked after Phase 1 design (passed).*

- **I — Privacy / E2EE**: N/A this phase — no networking, transport, crypto, or PII handling added; all
  data is local mock. No new secrets. **PASS.**
- **II — Spec as source of truth**: this plan derives from `spec.md` (clarified 2026-07-24). Any code↔doc
  drift is fixed in the same change-set (e.g. blueprint 04/07 gains a note that `watch()` is a
  change-signal over the cache; `AppThreadViewWidget` scroll-persistence verified). **PASS.**
- **III — Mandatory architecture blueprint**: builds to `docs/blueprints/mobile/` — Freezed BLoC,
  `RepositoryResult`, injectable+get_it DI, cache-first Sembast (04), `PagingState`-in-bloc paging (07)
  preserved (not replaced). **PASS.**
- **IV — Design-system fidelity**: no new visuals; design tokens only. Any golden change is limited to
  what the reactive behaviour necessitates (ordering), locked in both page-mobile + page-desktop. **PASS.**
- **V — Language discipline**: code/commits EN, docs/specs RU; UI microcopy EN; the stored `"You:"`
  attachment-preview prefix is a data-layer literal per the clarification (untranslated-in-DB debt,
  flagged). **PASS.**

No violations → Complexity Tracking is empty.

## Project Structure

### Documentation (this feature)

```text
specs/014-reactive-data-refresh/
├── plan.md              # this file
├── research.md          # Phase 0 (decisions R1–R4)
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/           # Phase 1 (repository + bloc contracts)
└── tasks.md             # /speckit-tasks (not created here)
```

### Source Code (repository root) — files this feature touches

```text
lib/
├── domain/repository/chat/
│   ├── chat_repository.dart          # + markChatRead(chatId)
│   └── message_repository.dart       # + watchMessages(chatId), + simulateIncoming(chatId) [debug]
├── data/
│   ├── local/chat/
│   │   ├── chat_dao.dart             # + getById(id) (record-key get)
│   │   └── message_dao.dart          # (watch already present)
│   └── repository/chat/
│       ├── chat_repository_impl.dart     # markChatRead
│       └── message_repository_impl.dart  # + ChatDao/ChatMapper deps, _touchChatRow, watchMessages, simulateIncoming
├── general/formatters/               # + chat_preview_formatter.dart (chatPreviewFor)
└── presentation/pages/
    ├── chats_list_page/bloc/         # loadChats(refresh), loadedPageCount, watchChats subscription
    │   └── chats_list_page.dart      # _threadPane empty-pane fallback (grafted)
    └── chat_thread_page/bloc/        # loadMessages(refresh), loadedPageCount, dedup-by-id, server-id adoption, markChatRead, watchMessages subscription

test/  # deep-mirrored: bloc_test for both blocs, repo tests (send→row, markChatRead, simulateIncoming),
       # dao test (getById), formatter test; goldens regenerated only if ordering changes
```

**Structure Decision**: single Dart package `nox_app`, Clean Architecture (presentation → domain ←
data). This feature is entirely presentation + data on the existing mock/DB seam; no new layer, package,
or platform channel.

## Complexity Tracking

No Constitution violations — section intentionally empty.

## Phase 1 outputs

- [data-model.md](data-model.md) — entities + the new data-layer operations (getById, markChatRead,
  _touchChatRow, watchMessages, simulateIncoming, chatPreviewFor) and the bloc state/event deltas.
- [contracts/](contracts/) — repository-method and BLoC event/state contracts.
- [quickstart.md](quickstart.md) — runnable validation scenarios (mobile + desktop).
