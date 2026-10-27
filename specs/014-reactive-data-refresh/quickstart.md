# Quickstart / Validation: Reactive data refresh (mocks)

**Feature**: 014-reactive-data-refresh · Phase 1

How to prove the feature works end-to-end. No backend — everything runs on the local Sembast DB.

## Prerequisites

- `make deps` (once). Run against the stage flavor: `fvm flutter run --dart-define-from-file=config/stage.json`
  (desktop: add `-d macos|windows|linux`).
- Automated: `make gate` (generate → format → analyze → test) and `make golden-verify` — both must be green.

## Manual validation (run the app)

Mobile (narrow window) AND desktop (wide window) — verify BOTH:

1. **Create → list (already shipped N1/N2, must still hold)**: tap `+`, create a chat → it appears in the
   list and its thread opens (mobile push / desktop select).
2. **Send updates the list live (US1/US2)**: open a chat, send a message → return to / look at the list:
   the chat's preview = the sent text, its time updates, and it jumps to the top — **without pull-to-refresh**.
   Desktop: the selected chat's row + detail pane update together, selection retained.
3. **Attachment preview (FR-003)**: send an attachment-only message → the chat row preview reads
   `"You: <filename>"`.
4. **Live thread (US3)**: with a thread open, use the debug **"Simulate incoming"** control (kDebugMode) →
   the message appears in the thread in chronological order without leaving/re-entering; your own just-sent
   messages still show pending→sent exactly once.
5. **Unread reset (US4)**: from the list, a chat with an unread badge → open it → badge drops to 0 live.
6. **Unread increment (US4)**: from a chat you are NOT viewing, trigger "Simulate incoming" for it → its
   list badge increments; the badge honours the 99+ cap.
7. **No scroll jump / no lost pages (FR-005/FR-008)**: scroll the list (load page 2) / scroll a long thread
   up (older history) → a live update must not reset the scroll offset or collapse the loaded pages.
8. **Failed send (FR-004)**: via the debug `sendError` scenario, send → the chat row is NOT updated to the
   un-accepted message.

## Automated validation (the acceptance harness)

- `make test FILE=test/presentation/pages/chats_list_page/bloc/chats_list_bloc_test.dart` — a DAO write
  drives a `refresh` tick; assert `loadedPageCount`, `query`, `selectedChatId` preserved and
  `items` ordering/preview/unread updated.
- `make test FILE=test/presentation/pages/chat_thread_page/bloc/chat_thread_bloc_test.dart` — one bubble
  across pending→sent (id adoption + dedup); `simulateIncoming` appears in order; older-history paging works.
- `make test FILE=test/data/repository/chat/message_repository_impl_test.dart` — send updates the chat row
  (preview/time/unread unchanged for own send); failed send leaves the row untouched; `simulateIncoming`
  increments unread.
- `make test FILE=test/data/repository/chat/chat_repository_impl_test.dart` — `markChatRead` resets to 0 and
  is a no-op at 0.
- `make test FILE=test/data/local/chat/chat_dao_test.dart` — `getById`.
- `make test FILE=test/general/formatters/chat_preview_formatter_test.dart` — text vs attachment preview.
- `make golden-verify` — regenerate 5.1/5.2 goldens ONLY if reactive ordering changes the rendered surface.

See [contracts/](contracts/) for the exact event/state/method contracts and [data-model.md](data-model.md)
for the operation list.
