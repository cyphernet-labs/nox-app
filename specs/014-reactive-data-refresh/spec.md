# Feature Specification: Reactive data refresh (mocks)

**Feature Branch**: `014-reactive-data-refresh`

**Created**: 2026-07-24

**Status**: Draft

**Input**: User description: "Реактивный рефреш данных на моках — список чатов (5.1) и тред (5.2) живо обновляются из локальной БД; отправка сообщения обновляет строку родительского чата (превью/время/порядок); unread растёт на входящем и сбрасывается при открытии чата; всё на mock cache-first репозиториях поверх реальной локальной Sembast-БД, сетевой слой остаётся мок; паритет mobile+desktop."

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Chats list stays current without manual refresh (Priority: P1)

As a user, when data behind the open chats list changes — a new chat is created, or a message is
sent in some chat — I want the chats list (5.1) to update **on its own** (last-message preview,
timestamp, and newest-first ordering, plus the new chat appearing), so I never see a stale list or
have to pull-to-refresh to catch up. This must behave identically on mobile (single list) and on
desktop (the list pane of the list-detail layout).

**Why this priority**: This is the user's headline complaint — data that does not refresh when it
changes elsewhere. It is the most visible correctness gap and the foundation the other stories build
on.

**Independent Test**: Open the chats list; from another surface create a chat and send a message in
an existing chat; without any manual refresh the list shows the new chat and the updated
preview/time/position. Verifiable on both `_narrow` and `_wide`.

**Acceptance Scenarios**:

1. **Given** the chats list is open, **When** a new chat is created, **Then** it appears in the list
   in its correct newest-first position without a manual refresh.
2. **Given** the chats list is open, **When** a message is sent in one of its chats, **Then** that
   chat's last-message preview and timestamp update and the chat moves to the top of the list.
3. **Given** the desktop list-detail layout, **When** the underlying chats change, **Then** the list
   pane reflects the change while the current detail selection is preserved (unless the selected chat
   is filtered out by an active search).
4. **Given** an active search query, **When** the underlying chats change, **Then** the visible list
   still honours the query (a change that does not match the query does not appear).

---

### User Story 2 — Sent message keeps the list and thread consistent (Priority: P1)

As a user, when I send a message in a chat, the chat's summary shown in the list (its last-message
preview and time) must match what I just sent, so the list and the open thread never disagree about
the chat's most recent activity.

**Why this priority**: This is the data-integrity cause behind Story 1's visible effect; without it
the reactive list would refresh but show stale summaries. Small, isolated, and unblocks Story 1.

**Independent Test**: Send a message in a chat, then inspect that chat's row summary — the preview
equals the sent message's text (or an attachment indicator) and the timestamp equals the send time.

**Acceptance Scenarios**:

1. **Given** a chat with an older last message, **When** I send a new message, **Then** the chat's
   stored last-message preview becomes the new message's text and its timestamp becomes the send time.
2. **Given** I send an attachment-only message, **When** the send completes, **Then** the chat's
   last-message preview shows a sensible attachment summary rather than empty text.
3. **Given** a message send fails, **When** the failure is surfaced, **Then** the chat row is **not**
   updated to a message that was never accepted.

---

### User Story 3 — The open thread updates live from local data (Priority: P2)

As a user, while I have a chat thread (5.2) open, new messages that land in that chat's local store
should appear in the thread without me leaving and re-entering, while my own just-sent messages keep
their optimistic lifecycle (sending → sent, or an error I can retry) and scrolling up still pages in
older history.

**Why this priority**: Establishes the live-thread seam and removes the "re-open to see changes"
gap. Lower than P1 because, with the API mocked, the primary live source is the user's own sends
(already optimistic) plus a mock-simulated inbound; full value arrives with a real backend.

**Independent Test**: With a thread open, cause a new message to land in that chat's store (own send,
or the debug "simulate incoming" affordance); it appears in the thread in order without a manual
reload, and paging up still loads older messages.

**Acceptance Scenarios**:

1. **Given** an open thread, **When** a new message is persisted for that chat, **Then** it appears in
   the thread in chronological position without a manual reload.
2. **Given** I send a message, **When** it is accepted, **Then** its bubble transitions from the
   pending to the sent state exactly once (no duplicate once the live store also reflects it).
3. **Given** I scroll to the top of a long thread, **When** more history exists, **Then** older
   messages page in as before.

---

### User Story 4 — Unread badges reflect reading (Priority: P3)

As a user, the unread badge on a chat should drop to zero once I open that chat (I have now read it),
and — when a new message arrives in a chat I am not viewing — its unread badge should go up, both
reflected live in the list.

**Why this priority**: Rounds out "data refreshes when it should". Reset-on-open is the real,
high-value half; increment-on-arrival is meaningful mainly via a mock-simulated inbound until a
backend exists.

**Independent Test**: Open a chat with a non-zero unread badge → its badge becomes zero in the list.
Trigger a mock inbound message for a chat you are not viewing → its badge increments in the list.

**Acceptance Scenarios**:

1. **Given** a chat with unread > 0, **When** I open it, **Then** its unread count resets to zero and
   the list badge disappears without a manual refresh.
2. **Given** a chat I am not currently viewing, **When** a new inbound message lands in it, **Then**
   its unread count increases by one and the list badge updates live.
3. **Given** the 99+ display cap, **When** a chat's unread exceeds the cap, **Then** the badge still
   renders the capped label.

### Edge Cases

- A message is sent in a chat that is **not** on the currently loaded page of the list — the chat
  must still surface (move to the top) rather than stay hidden below the fold.
- Rapid successive sends — the list settles on the latest message's preview/time and correct ordering
  without flicker or lost updates.
- Opening the thread of a brand-new chat that has only its own creation/first message — the thread and
  list stay consistent.
- On desktop, the selected chat receives a new message — its detail pane and its list row update
  together, and selection is retained.
- Unread reset must not fire for a chat merely rendered in the desktop list pane; only opening/viewing
  the chat counts as reading.

## Clarifications

### Session 2026-07-24

- Q: How is a "new inbound message" produced with the API mocked (no backend)? → A: A
  debug-only "Simulate incoming" affordance (a `kDebugMode` dev control) inserts an inbound
  message into the target chat's local store — deterministic and testable, mirroring the
  existing debug-scenario pattern. No automatic/periodic generation.
- Q: What marks a chat as read (resets unread), and what about the currently-viewed chat? → A:
  Viewing the thread marks it read — mobile push / desktop select (its thread shows in the pane);
  an inbound message that arrives in the currently-viewed chat stays read (no increment). Merely
  rendering a chat's row in the list is NOT reading.
- Q: What is the chats-list preview for an attachment-only message (no text)? → A: The attachment's
  filename with the usual author prefix (e.g. "You: design-spec.pdf") — no new l10n string, no emoji.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The chats list MUST reflect changes to the underlying chats (new chat, changed
  last-message preview/timestamp, changed ordering, changed unread) **without a manual refresh**,
  sourced from the local store.
- **FR-002**: Sending a message MUST update its parent chat's last-message preview and last-activity
  timestamp in the local store, and MUST reorder the chat to newest-first.
- **FR-003**: An attachment-only send MUST set the chat's last-message summary to the attachment's
  filename (with the usual author prefix, e.g. "You: design-spec.pdf") — never empty, no new l10n
  string, no emoji.
- **FR-004**: A failed send MUST NOT alter the parent chat's stored last-message summary or ordering.
- **FR-005**: The live list MUST continue to honour the active search query and the existing
  incremental "load more" paging (a reactive update must not discard already-loaded pages or the
  user's scroll position).
- **FR-006**: The open chat thread MUST reflect new messages persisted for that chat without a manual
  reload, in correct chronological order.
- **FR-007**: The optimistic send lifecycle (pending → sent, or error with retry) MUST be preserved,
  and a message MUST NOT appear twice when the live store also begins to reflect it.
- **FR-008**: Older-history paging in the thread (scroll up to load earlier messages) MUST continue to
  work alongside the live updates.
- **FR-009**: Viewing a chat's thread MUST reset that chat's unread count to zero, reflected live in
  the list badge — on mobile this is pushing the thread, on desktop it is selecting the chat (its
  thread renders in the detail pane). An inbound message that lands in the currently-viewed chat MUST
  stay read (no increment). Merely rendering a chat's row in the list is NOT reading.
- **FR-010**: A new inbound message for a chat the user is not viewing MUST increment that chat's
  unread count, reflected live in the list badge. Inbound is produced only by a debug-only
  "Simulate incoming" affordance (`kDebugMode` dev control) that persists an inbound message into
  the target chat's local store; there is no automatic/periodic generation.
- **FR-011**: All of the above MUST work identically on mobile (`_narrow`, single list / pushed thread)
  and desktop (`_wide`, list-detail with in-pane thread), preserving desktop selection across updates.
- **FR-012**: All data MUST come from the existing cache-first local store; the network layer stays
  mocked and no real transport/server is introduced.

### Key Entities

- **Chat**: an open-space conversation shown in the list — carries name, last-message preview,
  last-activity timestamp, and an unread count. Ordered newest-first by last activity.
- **Message**: an entry in a chat's thread — carries author, text and/or attachment, a send time, a
  local status (pending / sent / error), and a system flag; belongs to exactly one Chat.
- **Unread count**: per-chat number of messages not yet read by the local user; increases on a new
  inbound message and resets to zero when the chat is opened.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After creating a chat or sending a message, the chats list reflects the change with no
  manual refresh, in under 1 second, on both mobile and desktop.
- **SC-002**: In 100% of sends, the chat's list-row summary matches the last message shown in the
  thread (no list/thread disagreement).
- **SC-003**: A message a user sends never appears more than once in the thread across the
  optimistic-to-persisted transition.
- **SC-004**: Opening a chat with unread > 0 clears its badge to zero without a manual refresh in
  100% of cases.
- **SC-005**: A failed send leaves the chat's list summary unchanged in 100% of failure cases.
- **SC-006**: Every behaviour above is demonstrable in both the `_narrow` and `_wide` layouts.

## Assumptions

- **No real inbound from a server**: the API stays mocked (no backend is built). "New inbound message"
  is produced by a mock/debug-only affordance so the increment-on-arrival and live-thread behaviours
  are demonstrable now; the same reactive path will carry real inbound once a backend is wired.
- **Reset-on-open is the primary unread behaviour** (real, always-on); increment-on-arrival is
  exercised via the mock inbound.
- **Existing paging is retained**: the reactive list is reconciled with the current incremental
  "load more" model rather than replacing it; the small mock dataset means the full set is locally
  available.
- **Cache-first local store already exists** (chats + messages persist locally and survive restart);
  this feature adds reactive propagation and the send→chat-row update on top of it.
- **Message status stays local-only** (pending / sent / error); there are no delivered/read receipts
  (NOX open-space model).
- **Design/goldens**: no new visual design; any golden updates are only those the reactive behaviour
  necessitates (e.g. an updated list ordering), locked in both page-mobile and page-desktop categories.
