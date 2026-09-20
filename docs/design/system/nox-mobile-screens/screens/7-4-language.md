# 7.4 · Language

> **Settings** · mobile (iOS / Android) · Material 3

**Purpose.** Choose the app language.

## Anatomy
App bar (back + Language). Three single-select option cards - the same ones Appearance (7.3) uses, without the leading thumbnail: System, English, Українська.

## States
- `System` — System
- `English` — English
- `Українська` — Українська

## Behavior
- Single-select. System follows the OS locale and falls back to English if the OS is neither EN nor UK.
- Applies immediately.

## Navigation
- Back → Settings (7.1).

## Copy (EN)
- Options: System · English · Українська

## Design-system components
- AppBar (title)
- SelectOption (shared with 7.3 Appearance)

---
Live design: open `index.html` → 7.4 Language (switch states with the chips). Components are rendered from the shared design system (`_src/`).
