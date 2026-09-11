# 5.2 · Chat thread

> **Shell & Chats** · mobile (iOS / Android) · Material 3

**Purpose.** Read and send messages + files within one chat.

## Anatomy
App bar (back + chat name + a disabled **Invite a person** action). Message stream with date separators, author headers and bubbles. Composer pinned at bottom.
> **Changed 2026-09-10 (phase 037).** The client backend serves one person; talking to anybody else moves to a relay that does not exist yet. The invite is present as a disabled seam — the place the relay will attach to. The live screen in `_src/` draws it too. It did not at first, and the excuse written here — "the corpus AppBar has no disabled variant" — was wrong three times over: the blocker was one hardcoded colour in `m3.jsx`'s `actions.map`, while `IconButton` in the same shared file had always taken a `color`. `AppBar` actions now accept `{name, color}`, and the seam is dimmed to the M3 disabled 38% exactly as the app dims it.


## States
- `filled` — Filled
- `empty` — Empty
- `attachment` — Attachment
- `offline` — Offline

## Behavior
- Messages group by author; an AuthorHeader precedes each group (no per-message avatars in the feed).
- Own bubbles = primaryContainer (right, bottom-right corner clipped); others = surfaceContainerHigh (left, bottom-left clipped).
- Own message status: pending (schedule) → sent (check) → error (error, tinted error; tap to retry).
- Date separators: Today / Yesterday / 12 May. A system line marks chat creation.
- Empty: chat_bubble_outline empty-state. Offline: top banner + queued messages show pending.
- Composer: attach + text + send. Send enables when there is text or an attachment; attachment shows a removable chip above the row.
- The invite action is permanently disabled and raises nothing when tapped: a missing control answers «how do I add somebody?» with silence, an error answers it with a fault, and the truth is that the relay it needs does not exist yet. Its screen-reader name is the action alone — a disabled control is already announced as unavailable, and the caption that says it comes later lives under the button in 5.4, where there is room for it.
- Attachments in the feed: an IMAGE with a real local file renders an inline thumbnail (rounded, bubble-bounded); every other type — and an image with no/unavailable file — renders the type-icon chip (owner-revised F4).

## Navigation
- Back → Chats list (5.1).
- Attachment chip / file bubble → File view (5.3); an image thumbnail → full-screen image viewer (zoom / close) (F4).
- Tapping the chat name in the app bar opens the chat card (5.4).
- Invite action → nowhere: it is disabled and stays disabled until a relay exists.

## Copy (EN)
- System: Chat created by Aria
- Composer placeholder: Message
- Invite action (screen-reader name): Invite a person

## Design-system components
- AppBar (title)
- MsgBubble (+status)
- FileChip (in-bubble)
- DateSep / AuthorHeader / SystemLine
- Composer
- MaterialBanner
- EmptyState

---
Live design: open `index.html` → 5.2 Chat thread (switch states with the chips). Components are rendered from the shared design system (`_src/`).
