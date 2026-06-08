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
- Checking: trailing spinner during uniqueness check. Taken: errorText “This name is taken”, Create disabled.
- Valid → Create enabled. Submitting: button spinner.

## Navigation
- Create success → the new Chat thread (5.2).
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
