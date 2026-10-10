# 2.2 · QR scan

> ⚠️ **Feature 032, link format from 044, Connect from 045:** the scanner reads a pairing link `nox://pair/…` (version 3), not `nox://id/`, and passes the WHOLE payload on — the server's key and addresses are needed as much as the token. A code with no pairing link in it is refused here; a link from a newer app goes on to 2.1, which says to update the app. A scanned link takes the same path as a pasted one: 2.1 reads it and opens Connect (2.4). Windows and Linux have no camera: the same parser runs over a picked image there, and pasting text works everywhere.

> **Onboarding** · mobile (iOS / Android) · Material 3

**Purpose.** Scan a pairing link's QR code with the camera — the one on the server's service page, or an invite shown by another device of the same person.

## Anatomy
Live camera fills the screen. Transparent app bar (back, flashlight, switch-camera). Centered reticle with a 55% black mask (brand-fixed). Top instruction; bottom “Enter manually”.

## States
- `scan` — Scanning
- `denied` — Permission denied

## Behavior
- App bar over the feed has no surface fill and no splash hairline (splash=false).
- Reticle stroke is brand white (3dp), corners radius m; mask is #000 at 55% (brand-fixed, not themed).
- Detecting a pairing link closes the scanner at once: the link goes into the Login field, and Login reads it and opens Connect (2.4) — the same path as a pasted link (feature 045). A code that holds no pairing link → snackbar “This QR code is invalid. Try another one.”, and the camera keeps scanning.
- Permission denied → opaque surface screen (NOT over the camera) with no_photography glyph + “Open settings”.

## Navigation
- Valid scan → Login (2.1), which opens Connect (2.4) at once.
- Back → Login (2.1).
- Enter manually → Login (2.1).
- Open settings → OS settings.

## Copy (EN)
- Instruction: Aim your camera at a QR code
- Bottom: Enter manually
- Denied title: Camera access needed
- Denied body: To scan a QR code, allow camera access in system settings.
- Denied action: Open settings
- Invalid code (snackbar): This QR code is invalid. Try another one.

## Design-system components
- AppBar (splash=false, actions flashlight_on/cameraswitch)
- Brand: white, scrim mask
- Icon: no_photography
- FilledButton

---
Live design: open `index.html` → 2.2 QR scan (switch states with the chips). Components are rendered from the shared design system (`_src/`).
