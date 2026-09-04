# 03 · Set username

> **03 · Onboarding** · desktop (Windows / Linux / macOS) · Material 3 · window 1440×900

**Purpose.** Pick the display name — centered card.

**Adaptation from mobile.** mobile full-screen form → centered card

## Anatomy
Title bar (NOX · Set up) + OnboardCard with name field (counter N/32, helper), “Done”, “Skip”.

## States
- `prefilled` — Prefilled
- `empty` — Empty

## Behavior
- Same as mobile 2.3: pre-filled default, ≤32 chars, charset checked as typed. No availability check: person labels are **not unique** (owner, 2026-09-02), so there is no `checking`, no `taken` and no suffix spinner.

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
- TextField (counter)
- FilledButton
- TextButton

---
Live design: open `index.html` → 03 Set username (switch states with the chips). The desktop shell re-arranges the SAME widgets as mobile — only the wrapper differs.
