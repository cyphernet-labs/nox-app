# 6.1 · Create chat

> **Shell & Chats** · mobile (iOS / Android) · Material 3

**Purpose.** Create a new chat by unique name.

## Anatomy
App bar (back + “New chat”). Chat-name field with counter N/64. Pinned primary “Create”.

## States
- `valid` — Valid
- `checking` — Checking
- `taken` — Taken
- `loading` — Submitting
- `empty` — Empty

## Behavior
- Max 64 chars, charset unrestricted; counter updates live.
- Checking: trailing spinner during uniqueness check — the local store always, the server only when it can answer at once; a check the server cannot answer leaves the name valid. Taken: a chat on this device (one still waiting to be created included) or the server's answer; errorText “This name is taken”, Create disabled.
- Valid → Create enabled. Submitting: a local write, practically never visible.
- Create never waits for the server (phase 041): the chat is made on this device under an id minted there (`c_` + 32 lowercase hex, its id for good) and opens at once, with or without a connection. The outgoing queue creates it on the server before any of its messages. The server has the last word on the name then: a name taken by that time marks the chat for a rename in the list and the thread (5.1, 5.2).

## Navigation
- Create → the new Chat thread (5.2), at once, with or without a connection.
- Back → Chats list (5.1).

## Copy (EN)
- Label: Chat name
- Placeholder: e.g. Random thoughts
- Counter: N/64
- Error: This name is taken
- Primary: Create

## Design-system components
- AppBar (title)
- TextField (counter, spinner suffix)
- FilledButton (loading)

---
Live design: open `index.html` → 6.1 Create chat (switch states with the chips). Components are rendered from the shared design system (`_src/`).
