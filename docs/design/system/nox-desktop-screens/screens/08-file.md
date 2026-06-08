# 04 · File view

> **04 · Flows & dialogs** · desktop (Windows / Linux / macOS) · Material 3 · window 1440×900

**Purpose.** Inspect / download a file — a centered lightbox.

**Adaptation from mobile.** mobile pushed File view (5.3) → centered lightbox

## Anatomy
Heavier scrim + centered lightbox (520): header (type icon, name, download, close), large type glyph, name, size, Download.

## States
- `loaded` — Loaded
- `loading` — Downloading

## Behavior
- No content preview (type glyph). Downloading → determinate progress bar + “Downloading… N%”. Loaded → size + Download.

## Navigation
- Close / scrim → back to the thread.
- Download → saves to disk.

## Copy (EN)
- Size: 2.4 MB
- Progress: Downloading… 64%
- Action: Download

## Design-system components
- ChatsDesktop (base)
- FileViewDialog
- LinearProgress
- FileGlyph / fileColor
- FilledButton

---
Live design: open `index.html` → 04 File view (switch states with the chips). The desktop shell re-arranges the SAME widgets as mobile — only the wrapper differs.
