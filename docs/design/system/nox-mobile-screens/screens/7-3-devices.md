# 7.3 · Devices

> **Settings** · mobile (iOS / Android) · Material 3 · new in feature 032

**Purpose.** Show the keys allowed to speak as this person, and let any of them be cut off. Without it pairing has no undo and every lost device stays an open door.

## Anatomy
Detail scaffold (back + title). Current device in its own group, marked `This device`. Other devices in a second group, or the line `No other devices`. A filled `Add a device` button at the bottom; pressing it mints an invite and shows a card with the QR **and** the link as selectable text.

## States
- `loading` — always read from the server, never from a cache
- `loaded` — current device plus the others
- `alone` — nothing but this device
- `error` — Couldn't load your devices.
- `invite` — QR card, link valid for 10 minutes

## Behavior
- A row shows the OS family and two moments (paired, last seen). The key itself is never shown: 32 base64 bytes look identical across rows. The exact hardware model is deliberately not collected.
- `Revoke` opens a confirm dialog. Revoking the current device is a logout and says so in its own words.
- Revocation applies immediately — the revoked device's live connection drops rather than waiting for its next attempt.
- After a revoke the list is re-read from the server rather than edited locally.

## Copy (EN)
- Title: Devices
- This device · Revoke · Add a device · No other devices
- Revoke this device? / It will be signed out and won't be able to connect again.
- This is the device you're using. Revoking it signs you out here.
- Scan this from the other device. The link works for 10 minutes.

## Design-system components
- AppDetailScaffoldWidget, AppSettingsGroupWidget, ListTile rows, FilledButton, AppQrSurfaceWidget
