# 7.10 · Connection

> **Settings** · mobile (iOS / Android) · Material 3 · new in feature 045

**Purpose.** Where this device reaches the person's server, and whether Tor may be used: the same two addresses and the same Use Tor as Connect (2.4), after pairing.

## Anatomy
Detail scaffold: back arrow + title “Connection” + brand gradient hairline. Body, top to bottom: while there is no connection, one line in the `error` colour saying why; “Server address” and “Onion address” — the same field pair as 2.4 (outlined, single-line, URL keyboard, no autocorrection, no counter; “Optional” under the onion field while it is empty); “Save” (full-width filled button); “Could not save. Try again.” (centred, `error` colour) after a write that failed; then a settings card with one switch row — the `lan` glyph (bare, 22, `onSurfaceVariant`), the title “Use Tor”, the caption “NOX uses Tor only when it can't reach your server directly.” and the switch. The server key is never shown.

## States
- `loaded` — The fields show the addresses in effect: the person's own edit, else what the server says about itself (its public address; its onion address), else the pairing link's first direct address. Save is off.
- `edited` — A field differs from what is in effect and passes the format check: Save is on.
- `field-error` — A changed field fails the format check: “This isn't a valid server address.” / “This isn't a valid onion address.” under it, live while typing; Save stays off.
- `saving` — A write is under way: the fields and Save are disabled.
- `save-failed` — “Could not save. Try again.” under Save. A Use Tor switch that did not save has flipped back.
- `problem` — No connection: the line above the fields carries the cause, else “No connection”.

## Behavior
- The format rules are 2.4's, for what was changed: `host:port` (an IPv4 address, a bracketed IPv6 address or a DNS name; port 1–65535; never an onion name) and a version-3 onion address whose version byte and checksum hold. A value already in effect is not checked again.
- Save stores the edits and starts the connection again at once, so the next attempt goes by them. A value equal to what the server says counts as no edit: that field follows the server again from then on. An emptied onion field means no onion address. A server whose onion address moved is simply typed in here — no new pairing.
- Use Tor applies the moment it is switched and starts the connection again. Switched off, Tor stops at once and a connection that went through it is dropped: the device goes direct only. Switched on, Tor is tried whenever no direct address answers and an onion address is known; the device returns to the direct path as soon as it answers. Off by default, and per device — not synced.
- The server is the source of truth about its own addresses. A public or onion address it states replaces the person's edit of that field, and shows up in an untouched field while the section is open; a field the person is typing in keeps what they typed. An edit lasts until the server states that field again — it is there for a server the device cannot reach as it is.
- The line above the fields shows only while there is no connection — a whole round of path finding failed, or another server answered behind the onion address: one of the six causes (see 5.1), else “No connection”. It is a live region, and it goes the moment a connection is greeted.

## Navigation
- Arrives from Settings (7.1): the “Connection” row, directly under “Devices”.
- Back → Settings (7.1).

## Copy (EN)
- Title / row: Connection
- Fields: Server address · Onion address
- Onion helper (empty field): Optional
- Action: Save
- Save error: Could not save. Try again.
- Switch: Use Tor
- Caption: NOX uses Tor only when it can't reach your server directly.
- Field errors: This isn't a valid server address. · This isn't a valid onion address.
- No connection, cause unknown: No connection

## Design-system components
- AppDetailScaffold (back + title + hairline)
- TextField (outlined, single-line) ×2 — the same pair as Connect (2.4)
- FilledButton
- SettingsGroup / SettingsSwitchRow (glyph `lan`)

---
Behaviour spec only: this screen has no live design in `index.html`. Locked by the goldens `connection_page`, `connection_page_field_error` and `connection_page_problem`, at both widths.
