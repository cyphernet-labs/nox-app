# 5.3 · File view

> **Shell & Chats** · mobile (iOS / Android) · Material 3

**Purpose.** Inspect / download a single file - and, for a picture or a video, see it.

## Anatomy
App bar (back + file name + download action). Large type glyph in a tinted tile + file name + size.

## States
- `loaded` — Loaded
- `loading` — Downloading
- `open-error` — the plain copy a video plays from could not be made (phase 048)

## Behavior
- A video PLAYS here (owner revision, 2026-09-20) - frame, play/pause, scrub, timecode - and an image is SHOWN instead of described by a glyph. From the local file only: a native player uses its own HTTP stack, so it would reach the server around the 036 pin, and would fail the self-signed certificate anyway. Playback exists on iOS, Android and macOS; `video_player` has no Windows or Linux implementation, so there the screen is exactly what it was before playback existed. Every other type keeps the type glyph.
- Downloading: a determinate LinearProgress under the app bar (primary on surfaceVariant track) + “Downloading… N%”.
- Loaded: shows the file size.
- A broken link is not an error (phase 043): the bar stands still and the download goes on by itself from the byte it reached - and on after the screen is closed; reopened, it shows the same download where it stands. The error with Try again appears only once the server has refused again and again, and Try again goes on from the bytes already on the device.
- The file on the device is sealed (phase 048). A picture is opened into memory to be drawn - no plain copy on the disk. A video plays from a plain temporary copy in the app's own temporary folder, made once the bytes are here (the player's own wait meanwhile) and deleted when the screen closes with its player; whatever copies are left go at every launch and logout. A copy that cannot be made - no room on the disk - is said in place of the player, in the error colour: “Couldn't open this file. Free up some space and try again.” The file stays whole, and Download (Save) stays available; closing and opening the screen tries again.

## Navigation
- Back → previous (thread 5.2 or chat card 5.4).
- Download → writes the plain file where the person chose (phase 048: the copy on the device is sealed).

## Copy (EN)
- Size example: 2.4 MB
- Progress: Downloading… 64%
- Open error: Couldn't open this file. Free up some space and try again.

## Design-system components
- AppBar (title, action download)
- FileGlyph / fileColor
- LinearProgress
- Type: titleLarge + bodyMedium

---
Live design: open `index.html` → 5.3 File view (switch states with the chips). Components are rendered from the shared design system (`_src/`).
