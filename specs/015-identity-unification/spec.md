# Feature Specification: Unified Signed-In Identity (mocks)

**Feature Branch**: `015-identity-unification`

**Created**: 2026-07-25

**Status**: Draft

**Input**: User description: "Unified signed-in identity on mocks (no backend). Establish a single source of truth for the signed-in user's identity + display label, taken from the local session, replacing the three disconnected hardcoded constants (own-message author id/label + the Settings default label). (1) Own messages are authored with the user's chosen label and stable id from the session, not a hardcoded 'You'/'me'; (2) the Settings identity name loads from the session and renaming it persists to the session; (3) after a rename the desktop rail account-avatar label and the Settings display update live, not only after a restart. Preserve the two-layer identity model (technical anonymous identifier + public display label). All on the existing session store / mock data; the network layer stays mocked."

## Overview

Today the signed-in user's identity is expressed in **three unrelated places that can disagree**:

- the chat thread decides "own vs other" and authors the user's outgoing messages with a fixed placeholder identifier and the fixed label `You`;
- the Settings identity card shows a **compile-time default** label and never reads the label the user actually chose during onboarding;
- the desktop navigation-rail account avatar is the only surface that reads the *real* chosen label — seeded once when the shell is first shown.

As a result a user who signed in as `Alice` can simultaneously see `Alice` on the rail avatar, a stale default in Settings, and `You` on their own chat bubbles' underlying data. Worse, **renaming the label in Settings changes nothing that survives** — the change is held only in a screen's local state, is lost on restart, and never reaches the rail avatar.

This feature makes the **local session the single source of truth** for the signed-in identity (the technical identifier and the display label). Every surface reads its identity from that one source, a rename **persists** to that source, and the change is **broadcast live** to every surface currently on screen. The network/backend layer stays mocked and is not built.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - My own messages carry my real identity (Priority: P1)

As a signed-in user, when I open a chat and look at the conversation, my own messages are attributed to **me** (my signed-in identity) consistently — never to a stranger and never a hard-coded placeholder — so the thread always draws my messages on my side, both for history already in the chat and for messages I send now.

**Why this priority**: The own-vs-other split is the backbone of the thread UI. If own-detection is wrong, every other identity behaviour is moot. This story removes the hard-coded placeholder identity and is the foundation the other two build on.

**Independent Test**: Sign in with a known identity, open a chat that already contains own history plus other-author messages, and confirm own messages render on the own side and other-author messages on the other side. Send a new message and confirm it also lands on the own side. This is fully testable without touching Settings.

**Acceptance Scenarios**:

1. **Given** a signed-in user with a known identifier and label, **When** they open a chat thread, **Then** every message previously attributed to them renders on the own side and every other message on the other side.
2. **Given** an open chat thread, **When** the user sends a new message, **Then** the message is attributed to the signed-in identity (identifier + current chosen label) and renders on the own side.
3. **Given** two different signed-in identities in two separate app installs, **When** each opens the same chat, **Then** each sees *their own* messages on the own side (own-detection follows the session, not a shared constant).

---

### User Story 2 - Settings shows and remembers my chosen name (Priority: P1)

As a signed-in user, when I open Settings I see the display label I actually chose (not a default), and when I rename it the new label is remembered — it is still there after I close and reopen the app.

**Why this priority**: The identity card is where the user reads and edits their name. Showing a stale default is an obvious correctness bug, and a rename that silently evaporates on restart is a broken promise. This story is independently valuable even without the live-broadcast polish.

**Independent Test**: Sign in as `Alice`, open Settings, and confirm the name field shows `Alice`. Rename to `Alice2`, fully restart the app, reopen Settings, and confirm it still shows `Alice2`.

**Acceptance Scenarios**:

1. **Given** a signed-in user whose chosen label is `Alice`, **When** they open the Settings identity card, **Then** the name field shows `Alice` (the session label), not a compile-time default.
2. **Given** the Settings identity card, **When** the user edits the label to a valid, available new value and confirms, **Then** the new label is persisted to the session.
3. **Given** a label that was renamed and confirmed, **When** the app is fully restarted and Settings is reopened, **Then** the renamed label is shown.
4. **Given** the Settings name editor, **When** the user enters an invalid or already-taken label, **Then** the change is rejected by the existing validation and nothing is persisted.

---

### User Story 3 - A rename updates every surface live (Priority: P2)

As a signed-in user, when I rename my label in Settings, every place that shows my name updates immediately in the same session — I do not have to restart the app to see the new name on the desktop navigation-rail account avatar.

**Why this priority**: This is the "feels finished" polish on top of persistence. Persistence (US2) already fixes correctness; live broadcast removes the jarring restart-to-see-it gap, most visibly on desktop where the rail avatar and the Settings card are on screen at the same time.

**Independent Test**: On a desktop-width window, note the rail account-avatar label, rename the label in the Settings tab, and confirm the rail avatar reflects the new label within about a second, without any restart.

**Acceptance Scenarios**:

1. **Given** a desktop-width window showing the rail account avatar and the Settings tab, **When** the user renames their label and confirms, **Then** the rail account avatar updates to the new label without a restart.
2. **Given** any surface that displays the signed-in label, **When** a rename is confirmed, **Then** that surface converges to the new label without requiring the user to leave and re-enter it.
3. **Given** a rename that is rejected by validation, **When** the user abandons the edit, **Then** no surface changes its displayed label.

---

### Edge Cases

- **No session / read failure** when entering Settings or a chat thread: the surface degrades gracefully (empty or a stable fallback label, own-detection still renders a coherent thread) and never crashes; it never fabricates a fake identifier that could flow into the user's scannable `Your ID`.
- **Rename to the same current label**: treated as a no-op — nothing is persisted or broadcast, no error shown.
- **Cleared / empty cached label**: an empty stored label is treated as absent and the surface falls back to the default placeholder rather than showing a blank name.
- **Rename never reclassifies history**: because own-detection follows the stable technical identifier (which a rename does **not** change), renaming the label never moves an existing message from the own side to the other side or vice-versa.
- **Two live surfaces at once** (desktop rail avatar + Settings card): both converge to the same new label after a rename; they never end up showing two different labels.
- **Rename while the network layer is unavailable**: since the backend is mocked, a rename persists to the local session regardless; no connectivity gate blocks it.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The signed-in identity (technical identifier + display label) MUST have a single source of truth — the local session — that every user-facing surface reads from.
- **FR-002**: The chat thread MUST decide own-vs-other by comparing a message's author to the **signed-in identifier from the session**, replacing the hard-coded placeholder identifier.
- **FR-003**: Messages the user sends MUST be authored with the signed-in identity (identifier + the current chosen label from the session), replacing the hard-coded `me` / `You` placeholders.
- **FR-004**: Own-message history that already exists for the signed-in user MUST remain recognised as own after this change (own-detection must not regress existing seeded/own history to "other").
- **FR-005**: The Settings identity card MUST load and display the display label from the session, not a compile-time default; when no label is available it MUST fall back to the existing default placeholder.
- **FR-006**: Renaming the display label in Settings and confirming a valid, available value MUST persist the new label to the session.
- **FR-007**: A persisted rename MUST survive a full application restart (the renamed label is shown after relaunch).
- **FR-008**: Renaming MUST continue to enforce the existing label rules — display label is **case-sensitive unique**, **≤32 characters**, charset **`[A-Za-z0-9._-]`** — and MUST NOT persist an invalid or already-taken label.
- **FR-009**: The technical identifier MUST remain unchanged by a rename (only the display label changes); changing identity remains a Logout + re-login concern and is out of scope here.
- **FR-010**: After a confirmed rename, every on-screen surface that shows the signed-in label MUST update to the new label within the same session, without a restart — at minimum the Settings display and the desktop navigation-rail account avatar.
- **FR-011**: Renaming the label MUST NOT change any existing message's own/other classification.
- **FR-012**: All identity reads, persistence and broadcast MUST operate on the existing local session store and mock data; no real network/backend call is introduced.
- **FR-013**: Both layouts MUST honour this behaviour — the mobile (narrow) and desktop (wide) presentations must both read, persist and reflect the unified identity (the rail account avatar is a desktop-only surface, but the underlying identity source and the Settings behaviour are shared).
- **FR-014**: When the session cannot be read, identity-dependent surfaces MUST degrade to a coherent, non-crashing state (empty identifier for the scannable `Your ID`, a fallback label for display, a still-renderable thread).

### Key Entities *(include if feature involves data)*

- **Signed-in identity (session)**: the single record describing who the user is on this device.
  - *Technical identifier* — a stable, key-like anonymous string; secret; the value behind `Your ID`; unchanged by a rename; the basis for own-vs-other detection.
  - *Display label* — a public, human-readable name; mutable via rename; case-sensitive unique, ≤32 chars, charset `[A-Za-z0-9._-]`; shown in Settings and on the desktop rail avatar.
- **Message authorship**: each message carries the author's identifier (own = equals the session identifier) and an author label (display). Own bubbles are placed by identifier; the stored author label is the display name at send time.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On entering Settings, a signed-in user with a chosen label sees that exact label with no placeholder in 100% of cases.
- **SC-002**: A label renamed and confirmed is still shown after a full app restart in 100% of cases.
- **SC-003**: After a confirmed rename, the desktop rail account avatar reflects the new label within 1 second, with no restart.
- **SC-004**: Across the whole app at any moment, all identity surfaces (Settings label, rail avatar label, own-send author label) show the same label — 0 observed disagreements after any rename.
- **SC-005**: Own-vs-other classification is correct for both existing history and new sends — 0 misclassified messages in a chat that mixes own and other authors.
- **SC-006**: A rename causes 0 changes to any existing message's own/other side.

## Assumptions

- **Live-broadcast mechanism**: the rename is propagated to on-screen surfaces via a **reactive session/label signal** exposed by the session source, consistent with the project's established reactive-refresh pattern (a change-signal that surfaces subscribe to). A shell-local one-shot read is explicitly replaced. *(Design detail confirmed in planning.)*
- **Own-detection keys on the identifier**: own-vs-other follows the stable technical identifier (rename-invariant), so renaming can never reclassify messages. The display label is a separate, purely presentational attribute.
- **Seeded own history is reconciled to the signed-in identifier**: mock-seeded "own" messages are attributed to the signed-in identifier (not a separate `me` sentinel) so a single own-identity is used everywhere; a rename does not affect them.
- **Persistence reuses the existing session store**: the identifier stays in secure storage (unchanged), the label in the non-secret preferences store; no new backend uniqueness service is introduced — the existing case-sensitive mock-dataset uniqueness check remains the gate.
- **No retro-relabel of persisted history**: already-stored own messages keep the author label captured at send time (own bubbles do not display a label, so this has no visible effect); only new sends carry the newly chosen label. Retroactively rewriting historical labels is out of scope.
- **Thread own-identity is read at thread init** from the session; a failed/absent read degrades to a stable fallback so the thread still renders.
- **Scope boundaries**: real backend identity/uniqueness endpoints, changing the technical identifier without logout, a profile screen (NOX has none), and multi-account are all out of scope. The mobile fallback for the desktop-only rail avatar is that the avatar simply does not appear on narrow layouts (unchanged).
