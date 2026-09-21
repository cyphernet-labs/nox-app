# 7.4 · Language

> **Settings** · mobile (iOS / Android) · Material 3

**Purpose.** Choose the app language.

## Anatomy
App bar (back + Language). Three single-select option cards - the same ones Appearance (7.3) uses - each with a 64x48 leading tile: System, English, Українська. Flags for the two languages; for System the device glyph, which is what the option follows.

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
- LanguagePreview (flag tile / device glyph tile)

---
Live design: open `index.html` → 7.4 Language (switch states with the chips). Components are rendered from the shared design system (`_src/`).
