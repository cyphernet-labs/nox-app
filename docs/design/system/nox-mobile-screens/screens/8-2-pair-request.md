# 8.2 · Pair request

> **Over any screen** · mobile (iOS / Android) · Material 3 · new in feature 046

**Purpose.** Ask the person whether a new device may join. A device that presents an invite this device issued waits until it is answered here: an invite pairs nothing without Allow, so a leaked QR code is worth nothing.

## Anatomy
A Material 3 AlertDialog centred over whatever screen is up, with the modal scrim (`NoxOpacity.scrim`). Top to bottom: the `devices` glyph in `secondary`; the question “New device: {platform}. Allow it to join?” (bodyLarge, `onSurface`, centred); when an answer did not get through, “Couldn't send your answer. Try again.” under it (bodyMedium, `error`, centred, a live region); actions at the end: “Deny”, then “Allow”, both text buttons.

`{platform}` is the new device's OS family in the app's own words — “iPhone or iPad” · “Android” · “Mac” · “Windows” · “Linux”, and “Unknown system” for anything else. No text from the wire ever reaches the dialog: a leaked invite must not be able to call itself whatever it likes in the question that asks to let it in. No hardware model is sent at all.

## States
- `asking` — The question, both buttons enabled.
- `answering` — One button pressed: a spinner in its place, both buttons disabled.
- `answer-failed` — The answer did not reach the server: the error line under the question, both buttons enabled again.
- `several` — More than one request waits: the oldest is asked about; the next one waits its turn and comes up when this one closes. What was said about the last question (an answer on its way, one that failed) does not carry over.
- `closed-elsewhere` — The request closed without an answer from here: the dialog goes without a word.

## Behavior
- Shown only on a signed-in screen (the shell and anything above it), only while the app is open and connected: the server tells the issuing device's greeted connections and tells them again after each of its greetings, so the question comes back with the connection. Never on the splash or the onboarding screens - a request is only ever addressed to a paired device. There are no notifications: with the app closed the request waits until the invite's ten minutes run out, and expires.
- Allow pairs the new device as the same person; the device list (7.8) updates itself on every device, and the invite card on this one goes.
- Deny closes the request and spends the invite; the new device says “Your other device declined this request.” (2.4).
- It cannot be put aside: the scrim, system back and Escape do nothing. A request left unanswered would only come back with the next greeting.
- It goes away when the request ends any other way - its time ran out, the new device pressed Cancel, another connection of this device answered, a revocation closed it - and when the connection drops; a request that still waits comes back with the next greeting, one that closed meanwhile does not.
- An answer to a request that closed meanwhile is not an error: the dialog just goes.
- The answer goes out only over the greeted connection: an answer queued for a later connection could reach a request that closed in between.

## Navigation
- Appears over any signed-in screen; closes back to the same screen.

## Copy (EN)
- Question: New device: {platform}. Allow it to join?
- Actions: Deny · Allow
- Answer not sent: Couldn't send your answer. Try again.
- Families: iPhone or iPad · Android · Mac · Windows · Linux · Unknown system

## Design-system components
- AlertDialog (M3) with an icon; a barrier that does not dismiss
- TextButton ×2, a spinner inside the pressed one
- Icon: devices

---
Behaviour spec only: this dialog has no live design in `index.html`. Locked by the goldens `app_pair_request_dialog_widget` and `app_pair_request_dialog_widget_failed`, at both widths.
