# 5.3 · File view

> **Shell & Chats** · mobile (iOS / Android) · Material 3

**Purpose.** Inspect / download a single file - and, for a picture or a video, see it.

## Anatomy
App bar (back + file name + download action). Large type glyph in a tinted tile + file name + size.

## States
- `loaded` — Loaded
- `loading` — Downloading

## Behavior
- A video PLAYS here (owner revision, 2026-09-20) - frame, play/pause, scrub, timecode - and an image is SHOWN instead of described by a glyph. From the local file only: a native player uses its own HTTP stack, so it would reach the server around the 036 pin, and would fail the self-signed certificate anyway. Playback exists on iOS, Android and macOS; `video_player` has no Windows or Linux implementation, so there the screen is exactly what it was before playback existed. Every other type keeps the type glyph.
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
