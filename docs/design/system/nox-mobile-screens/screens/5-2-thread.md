# 5.2 · Chat thread

> **Shell & Chats** · mobile (iOS / Android) · Material 3

**Purpose.** Read and send messages + files within one chat.

## Anatomy
App bar (back + chat name). Message stream with date separators, author headers and bubbles. Composer pinned at bottom.

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

## Navigation
- Back → Chats list (5.1).
- Attachment chip / file bubble → File view (5.3).
- (Header affordances to chat card exist on desktop; mobile reaches files via 5.4 entry.)

## Copy (EN)
- System: Chat created by Aria
- Composer placeholder: Message

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
