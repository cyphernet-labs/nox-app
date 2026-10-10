# 2.4 · Connect

> **Onboarding** · mobile (iOS / Android) · Material 3 · new in feature 045

**Purpose.** Show where a pairing link leads before the device pairs, let the person change it, and pair. Every way a link arrives — pasted, scanned, read from a QR image — ends on this screen; Login (2.1) only reads the link.

## Anatomy
App bar: back arrow (left), centred NOX wordmark, brand gradient hairline under it. Scrollable body: the title “Connect to your server” (titleLarge, centred); a “Server address” outlined single-line field; an “Onion address” outlined single-line field, with the helper “Optional” while it is empty; a “Use Tor” checkbox row — leading checkbox, title “Use Tor”, caption “NOX uses Tor only when it can't reach your server directly.” Pinned at the bottom: “Connect” (full-width pill primary button), the reason line under it when there is one (bodyMedium, `error` colour, centred), then “Cancel” (full-width text button). Both fields take a URL keyboard, with no autocorrection, no suggestions and no counter. The server key the link carries is never shown and never editable.

## States
- `filled` — Filled from the link: Server address = the link's first direct address (the server's public address when it set one, because a link lists public → direct → onion); Onion address = the `<56>.onion` the link's onion service key derives (host only, no `:443`); Use Tor off.
- `no-onion` — The link carries no onion address: the onion field is empty and shows “Optional”.
- `field-error` — Connect was pressed with an edited value that is not an address: “This isn't a valid server address.” / “This isn't a valid onion address.” under that field; nothing is sent.
- `connecting` — Pairing under way: a spinner inside Connect; the fields, the checkbox, the back arrow and Cancel are disabled, and system back does nothing.
- `failed` — One line in the `error` colour under Connect says why (see Behavior); the fields keep what they hold.

## Behavior
- The format check runs on Connect, over what was EDITED only: a value equal to the link's own passes as it is. Server address — `host:port`: an IPv4 address, an IPv6 address in brackets or a DNS name, port 1–65535, never an onion name. Onion address — a version-3 address: 56 base32 characters and `.onion`, any case, with or without `:443`, whose version byte and checksum hold (the checksum through the app's Tor module). Once shown, a field error follows the typing live.
- Connect pairs with what the screen shows. The device tries directly first — the link's direct addresses and the one in the field — and through Tor only when Use Tor is ticked and an onion address is known. The same holds for the very first device of a server (the claim) as for any later one.
- The pairing token goes out only on a connection where the server proved the key the link names, whatever address or path it took. That is what makes a hand edit safe: an address that leads to another machine never sees the token.
- A cause found while the attempt is still running shows under Connect at once, not when the attempt gives up. The line is a live region, so a screen reader says it as it appears.
- Failed — the line under Connect is one of:
  - a known cause: “No server answers at this onion address. Check the address and that Tor is running on the server.” · “Your server isn't answering through Tor right now. Check that it is running.” · “This onion address belongs to a different server.” · “Can't connect to the Tor network. Check your internet connection.” · “Can't reach the server directly. Turn on Use Tor to connect through Tor.”;
  - no known cause: “Could not sign in. Check your connection and try again.”;
  - the server refused the link's token: “This link has expired. Ask for a new one.” or “This link can't be used. Ask for a new one.”
- An onion address the Tor module refused as not version 3 is said once, at the onion field (“This isn't a valid onion address.”), not under Connect.
- Any edit — a field or the checkbox — clears the line: it was about the settings that were there then.
- Paired: the usual flow takes over. What differs from the link is stored as the person's own edit, and Use Tor as ticked; both stay editable in Connection (7.10).
- Use Tor is off by default and belongs to this device; it is not synced to the person's other devices. Tor works on all five platforms.

## Navigation
- Arrives from Login (2.1): Sign in on a pasted link, or a scan on QR scan (2.2), which hands the link to 2.1.
- Back arrow / Cancel / system back → Login (2.1), with the link still in its field. Not while connecting.
- Paired → Set username (2.3) when the pairing created the person (a claim), else Chats (5.1) — by the app-state spine, not by this screen.

## Copy (EN)
- Title: Connect to your server
- Fields: Server address · Onion address
- Onion helper (empty field): Optional
- Checkbox: Use Tor
- Caption: NOX uses Tor only when it can't reach your server directly.
- Primary: Connect
- Secondary: Cancel
- Back (tooltip): Back
- Field errors: This isn't a valid server address. · This isn't a valid onion address.
- Reasons: the five causes above · Could not sign in. Check your connection and try again. · This link has expired. Ask for a new one. · This link can't be used. Ask for a new one.

## Design-system components
- AppBar (back, wordmark, splash hairline)
- TextField (outlined, single-line) ×2 — the same pair as Connection (7.10)
- CheckboxListTile
- FilledButton (pill, loading)
- TextButton

---
Behaviour spec only: this screen has no live design in `index.html`. Locked by the goldens `connect_page`, `connect_page_no_onion`, `connect_page_field_error` and `connect_page_reason`, at both widths.
