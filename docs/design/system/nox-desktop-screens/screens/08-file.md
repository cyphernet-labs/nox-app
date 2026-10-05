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
- A video PLAYS here (owner revision, 2026-09-20) - frame, play/pause, scrub, timecode - and an image is SHOWN instead of described by a glyph. From the local file only: a native player uses its own HTTP stack, so it would reach the server around the 036 pin, and would fail the self-signed certificate anyway. Playback exists on iOS, Android and macOS; `video_player` has no Windows or Linux implementation, so there the screen is exactly what it was before playback existed. Every other type keeps the type glyph. Downloading → determinate progress bar + “Downloading… N%”. Loaded → size + Download.
- A broken link is not an error (phase 043): the bar stands still and the download goes on by itself from the byte it reached - and on after the screen is closed; reopened, it shows the same download where it stands. The error with Try again appears only once the server has refused again and again, and Try again goes on from the bytes already on the device.

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
