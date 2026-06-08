# 5.3 · File view

> **Shell & Chats** · mobile (iOS / Android) · Material 3

**Purpose.** Inspect / download a single file. No in-app content preview.

## Anatomy
App bar (back + file name + download action). Large type glyph in a tinted tile + file name + size.

## States
- `loaded` — Loaded
- `loading` — Downloading

## Behavior
- No content preview — a large file-type glyph stands in (brand-tinted by type).
- Downloading: a determinate LinearProgress under the app bar (primary on surfaceVariant track) + “Downloading… N%”.
- Loaded: shows the file size.

## Navigation
- Back → previous (thread 5.2 or chat card 5.4).
- Download → saves to device.

## Copy (EN)
- Size example: 2.4 MB
- Progress: Downloading… 64%

## Design-system components
- AppBar (title, action download)
- FileGlyph / fileColor
- LinearProgress
- Type: titleLarge + bodyMedium

---
Live design: open `index.html` → 5.3 File view (switch states with the chips). Components are rendered from the shared design system (`_src/`).
