# 12 · Connection

> **Settings** · desktop (macOS / Windows / Linux) · Material 3 · new in feature 045

**Purpose.** Where this device reaches the person's server, and whether Tor may be used: the same two addresses and the same Use Tor as Connect, after pairing.

**Adaptation from mobile.** mobile pushed Connection screen (7.10) → the Settings detail pane; the body is the same widget at both widths

## Anatomy
Fills the Settings detail pane (02); no push, selection swaps the pane. The menu item “Connection” sits in the FIRST menu group, after Account and Devices; selected, it fills `secondaryContainer` and its `lan` glyph swaps to the filled variant. Pane title “Connection”; the content column is capped like every settings pane (≤680). Top to bottom: while there is no connection, one line in the `error` colour saying why; “Server address”; “Onion address” (“Optional” while empty); “Save” (full-width filled button); “Could not save. Try again.” after a write that failed; then a settings card with the “Use Tor” switch row (`lan` glyph, title, caption). The server key is never shown.

## States
- `loaded` — The addresses in effect: the person's own edit, else what the server says about itself, else the pairing link's first direct address. Save off.
- `edited` — A changed field passes the format check: Save on.
- `field-error` — A changed field fails it: the error under the field, live; Save off.
- `saving` — Fields and Save disabled.
- `save-failed` — “Could not save. Try again.”; a Use Tor switch that did not save has flipped back.
- `problem` — No connection: the cause above the fields, else “No connection”.

## Behavior
- Same as mobile 7.10. Save stores the edits — a value equal to the server's counts as no edit, so that field follows the server again — and starts the connection again at once; a moved onion address is typed in, no new pairing; an emptied onion field means no onion address.
- Use Tor applies the moment it is switched and starts the connection again; switched off, Tor stops at once and a connection through it is dropped. Off by default, per device.
- Addresses the server states replace the person's edit of the same field and show up in untouched fields while the pane is open; a field being typed in keeps what was typed.
- The line above the fields shows only while there is no connection: one of the six causes (see 01 · Chats), else “No connection”; a live region.

## Navigation
- Menu item “Connection” → this pane.
- Another menu item → swaps the pane.

## Copy (EN)
- Menu item / pane title: Connection
- Fields: Server address · Onion address
- Onion helper (empty field): Optional
- Action: Save
- Save error: Could not save. Try again.
- Switch: Use Tor
- Caption: NOX uses Tor only when it can't reach your server directly.
- Field errors: This isn't a valid server address. · This isn't a valid onion address.
- No connection, cause unknown: No connection

## Design-system components
- SettingsNavItem (glyph `lan`, filled when selected)
- PaneHeader
- TextField (outlined, single-line) ×2
- FilledButton
- SettingsGroup / SettingsSwitchRow

---
Behaviour spec only: this pane has no live design in `index.html`. Locked by the desktop goldens `connection_page_desktop`, `connection_page_field_error_desktop`, `connection_page_problem_desktop` and `settings_root_page_connection_desktop`.
