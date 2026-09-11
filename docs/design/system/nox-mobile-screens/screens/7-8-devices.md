# 7.8 · Devices

> **Settings** · mobile (iOS / Android) · Material 3 · new in feature 032

**Purpose.** Show the keys allowed to speak as this person, and let any of them be cut off. Without it pairing has no undo and every lost device stays an open door.

## Anatomy
Detail scaffold (back + title). Current device in its own group, marked `This device`. Other devices in a second group, or the line `No other devices`. A filled `Add a device` button at the bottom; pressing it mints an invite and shows a card with the QR **and** the link as selectable text.

## States
- `loading` — always read from the server, never from a cache
- `loaded` — current device plus the others
- `alone` — nothing but this device
- `error` — Couldn't load your devices.
- `action error` — Couldn't revoke that device. Try again. (its own line above the list, never the list's)
- `invite` — QR card, link valid for 10 minutes

## Behavior
- A row shows the OS family and two moments (paired, last seen). The key itself is never shown: 32 base64 bytes look identical across rows. The exact hardware model is deliberately not collected.
- `Revoke` opens a confirm dialog. Revoking the current device is a logout and says so in its own words.
- Revocation applies immediately — the revoked device's live connection drops rather than waiting for its next attempt.
- A device paired from elsewhere appears in the open list on its own (phase 038): the server says so, and the screen re-reads. Leaving the section and coming back is no longer how you find out.
- The invite card disappears when a device joins — the token is one-shot and spent, and a QR the server will now refuse is worse than no QR.
- The list is also re-read when the live channel comes back: the pairing event does not survive a disconnect, and the person whose connection blinked would otherwise keep a wrong list.
- A revoke that fails says so in its own sentence, above the list. Separate from the load error since phase 038: the screen now re-reads
  the list by itself, so a revoke can fail on a list that loaded fine, and one shared sentence would blame the wrong thing.
- That notice belongs to ONE device, and leaves on either of two events: another attempt on the same device (the person is retrying it),
  or a list that comes back without that device at all. The second is not a formality - a revoke whose reply was lost still happened, and
  once the row is gone there is nothing left to press "try again" on. Revoking a DIFFERENT device does not take it down: the first one is
  still authorised, and this sentence is the only thing that says so.
- After a revoke the list is re-read from the server rather than edited locally. That read keeps the list on screen - no spinner - but it
  does report its own failure: the person asked for it, and silence would leave the revoked device listed with nothing to explain it.

## Copy (EN)
- Title: Devices
- This device · Revoke · Add a device · No other devices
- Revoke this device? / It will be signed out and won't be able to connect again.
- This is the device you're using. Revoking it signs you out here.
- Scan this from the other device. The link works for 10 minutes.

## Design-system components
- AppDetailScaffoldWidget, AppSettingsGroupWidget, ListTile rows, FilledButton, AppQrSurfaceWidget
