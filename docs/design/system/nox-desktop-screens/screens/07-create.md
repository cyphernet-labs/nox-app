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
- Same validation: ≤64 chars, live uniqueness (spinner) — the local store always, the server only when it can answer at once — taken → error + Create disabled.
- Create never waits for the server (phase 041): the chat is made on this device under an id minted there and the dialog closes onto it at once, with or without a connection; submitting is a local write, practically never visible. The outgoing queue creates it on the server before its messages, and a name taken by then marks the chat for a rename (01 Chats).

## Navigation
- Create → opens the new thread in the right pane, at once.
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
