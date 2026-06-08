# 2.2 · QR scan

> **Onboarding** · mobile (iOS / Android) · Material 3

**Purpose.** Scan another device’s ID QR with the camera.

## Anatomy
Live camera fills the screen. Transparent app bar (back, flashlight, switch-camera). Centered reticle with a 55% black mask (brand-fixed). Top instruction; bottom “Enter manually”.

## States
- `scan` — Scanning
- `denied` — Permission denied

## Behavior
- App bar over the feed has no surface fill and no splash hairline (splash=false).
- Reticle stroke is brand white (3dp), corners radius m; mask is #000 at 55% (brand-fixed, not themed).
- Detecting a valid code signs in immediately (same outcome as Login success).
- Permission denied → opaque surface screen (NOT over the camera) with no_photography glyph + “Open settings”.

## Navigation
- Valid scan → Set username (2.3) / Chats (5.1).
- Back → Login (2.1).
- Enter manually → Login (2.1).
- Open settings → OS settings.

## Copy (EN)
- Instruction: Aim your camera at a QR code
- Bottom: Enter manually
- Denied title: Camera access needed
- Denied body: To scan a QR code, allow camera access in system settings.
- Denied action: Open settings

## Design-system components
- AppBar (splash=false, actions flashlight_on/cameraswitch)
- Brand: white, scrim mask
- Icon: no_photography
- FilledButton

---
Live design: open `index.html` → 2.2 QR scan (switch states with the chips). Components are rendered from the shared design system (`_src/`).
