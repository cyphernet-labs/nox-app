# 7.3 · Appearance

> **Settings** · mobile (iOS / Android) · Material 3

**Purpose.** Choose the theme: System / Light / Dark.

## Anatomy
App bar (back + Appearance). Three theme option cards, each a mini preview thumbnail + label + radio.

## States
- `System` — System
- `Light` — Light
- `Dark` — Dark

## Behavior
- Single-select radio cards; the selected card is outlined primary + filled surface.
- System matches the OS; selection maps to Flutter ThemeMode.{system,light,dark}.
- Applies immediately, app-wide.

## Navigation
- Back → Settings (7.1).

## Copy (EN)
- Options: System / Match your device · Light / Always light · Dark / Always dark

## Design-system components
- AppBar (title)
- ThemeOptionCard (radio + thumbnail)

---
Live design: open `index.html` → 7.3 Appearance (switch states with the chips). Components are rendered from the shared design system (`_src/`).
