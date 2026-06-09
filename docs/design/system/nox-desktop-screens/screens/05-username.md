# 03 · Set username

> **03 · Onboarding** · desktop (Windows / Linux / macOS) · Material 3 · window 1440×900

**Purpose.** Pick the display name — centered card.

**Adaptation from mobile.** mobile full-screen form → centered card

## Anatomy
Title bar (NOX · Set up) + OnboardCard with name field (counter N/32, helper), “Done”, “Skip”.

## States
- `prefilled` — Prefilled
- `checking` — Checking
- `taken` — Taken
- `empty` — Empty

## Behavior
- Same as mobile 2.3: pre-filled default, ≤32 chars, live uniqueness (spinner), taken → error + Done disabled.

## Navigation
- Done / Skip → Chats (01).

## Copy (EN)
- Label: Name
- Counter: N/32
- Helper: Others see this name. You can change it now or later in Settings.
- Primary: Done · Secondary: Skip

## Design-system components
- DesktopWindow + TitleBar
- OnboardCard
- TextField (counter, spinner)
- FilledButton
- TextButton

---
Live design: open `index.html` → 03 Set username (switch states with the chips). The desktop shell re-arranges the SAME widgets as mobile — only the wrapper differs.
