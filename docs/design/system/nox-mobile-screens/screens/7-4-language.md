# 7.4 · Language

> **Settings** · mobile (iOS / Android) · Material 3

**Purpose.** Choose the app language.

## Anatomy
App bar (back + Language). Grouped radio rows with a leading flag/glyph: System, English, Українська.

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
- SettingsGroup / LangRow
- FlagUK / FlagUA / SysCircle

---
Live design: open `index.html` → 7.4 Language (switch states with the chips). Components are rendered from the shared design system (`_src/`).
