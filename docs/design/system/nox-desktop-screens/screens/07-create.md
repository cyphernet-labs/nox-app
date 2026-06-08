# 04 · Create chat

> **04 · Flows & dialogs** · desktop (Windows / Linux / macOS) · Material 3 · window 1440×900

**Purpose.** Create a chat — a centered modal dialog over the chats window.

**Adaptation from mobile.** mobile pushed screen (6.1) → centered dialog

## Anatomy
Scrim + centered Dialog (460): “New chat”, chat-name field (counter N/64), Cancel + Create.

## States
- `valid` — Valid
- `checking` — Checking
- `taken` — Taken
- `loading` — Submitting
- `empty` — Empty

## Behavior
- Mobile’s pushed 6.1 screen becomes a centered dialog over the (deselected) chats window.
- Same validation: ≤64 chars, live uniqueness (spinner), taken → error + Create disabled, submitting → spinner.

## Navigation
- Create → opens the new thread in the right pane.
- Cancel / scrim → dismiss.

## Copy (EN)
- Title: New chat
- Label: Chat name
- Counter: N/64
- Error: This name is taken
- Cancel · Create

## Design-system components
- ChatsDesktop (base)
- CreateChatDialog
- TextField (counter, spinner)
- FilledButton / TextButton

---
Live design: open `index.html` → 04 Create chat (switch states with the chips). The desktop shell re-arranges the SAME widgets as mobile — only the wrapper differs.
