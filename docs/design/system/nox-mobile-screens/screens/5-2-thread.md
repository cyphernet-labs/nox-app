# 5.2 · Chat thread

> **Shell & Chats** · mobile (iOS / Android) · Material 3

**Purpose.** Read and send messages + files within one chat.

## Anatomy
App bar (back + chat name + a disabled **Invite a person** action). Message stream with date separators, author headers and bubbles. Composer pinned at bottom.
> **Изменено 2026-09-10 (фаза 037).** Клиент-бэкенд обслуживает одного человека; общение с другими людьми уходит на relay, которого ещё нет. Приглашение присутствует как выключенный шов — место, к которому relay прирастёт.


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
- (Header affordances to chat card exist on desktop; mobile reaches files via 5.4 entry.)

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
