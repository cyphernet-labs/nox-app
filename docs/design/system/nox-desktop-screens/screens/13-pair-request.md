# 04 · Pair request

> **04 · Flows & dialogs** · desktop (Windows / Linux / macOS) · Material 3 · window 1440×900 · new in feature 046

**Purpose.** Ask the person whether a new device may join, over whatever the window shows. A device that presents an invite this device issued waits until it is answered here.

**Adaptation from mobile.** none - the same AlertDialog as mobile 8.2, centred over the whole window: title bar, navigation rail and panes alike

## Anatomy
Scrim over the whole window + centred AlertDialog: the `devices` glyph in `secondary`, “New device: {platform}. Allow it to join?” (bodyLarge, centred), the error line “Couldn't send your answer. Try again.” when an answer did not get through (bodyMedium, `error`, a live region), then “Deny” and “Allow” at the end. `{platform}` is one of “iPhone or iPad” · “Android” · “Mac” · “Windows” · “Linux”, or “Unknown system” - the app's own words, never text from the wire.

## States
- `asking` — Both buttons enabled.
- `answering` — A spinner in the pressed button; both disabled.
- `answer-failed` — The error line; both buttons enabled again.
- `several` — The oldest request first; the next comes up when this one closes.
- `closed-elsewhere` — The request closed without an answer from here: the dialog goes without a word.

## Behavior
- Same rules as mobile 8.2: only on a signed-in window, only while the app is open and connected (the server asks again after each greeting); it cannot be put aside - the scrim and Escape do nothing; it goes when the request ends any way or the connection drops; an answer to a request that closed meanwhile is not an error; the answer goes out only over the greeted connection.
- Allow pairs the new device as the same person and the device list updates itself on every device; Deny spends the invite and the new device says “Your other device declined this request.” (03 · Connect).

## Navigation
- Appears over any signed-in window state; closes back to it.

## Copy (EN)
- Question: New device: {platform}. Allow it to join?
- Actions: Deny · Allow
- Answer not sent: Couldn't send your answer. Try again.
- Families: iPhone or iPad · Android · Mac · Windows · Linux · Unknown system

## Design-system components
- AlertDialog (M3), non-dismissible barrier
- TextButton ×2 with an in-button spinner

---
Behaviour spec only: this dialog has no live design in `index.html`. Locked by the desktop goldens `app_pair_request_dialog_widget_desktop` and `app_pair_request_dialog_widget_failed_desktop`.
