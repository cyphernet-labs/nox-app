# 2.4 · Connect

> **Onboarding** · mobile (iOS / Android) · Material 3 · new in feature 045 · the wait for approval since feature 046

**Purpose.** Show where a pairing link leads before the device pairs, let the person change it, and pair. Every way a link arrives — pasted, scanned, read from a QR image — ends on this screen; Login (2.1) only reads the link.

A link is one of two kinds, and only the server's answer tells them apart. A **machine link** (the server's service page, or `noxd link`) pairs at once. An **invite** from one of the person's devices pairs only once that device answers Allow: until then this screen waits, and the question is asked there (8.2 · Pair request).

## Anatomy
App bar: back arrow (left), centred NOX wordmark, brand gradient hairline under it. Scrollable body: the title “Connect to your server” (titleLarge, centred); a “Server address” outlined single-line field; an “Onion address” outlined single-line field, with the helper “Optional” while it is empty; a “Use Tor” checkbox row — leading checkbox, title “Use Tor”, caption “NOX uses Tor only when it can't reach your server directly.” Pinned at the bottom: “Connect” (full-width pill primary button), the reason line under it when there is one (bodyMedium, `error` colour, centred), then “Cancel” (full-width text button). Both fields take a URL keyboard, with no autocorrection, no suggestions and no counter. The server key the link carries is never shown and never editable.

## States
- `filled` — Filled from the link: Server address = the link's first direct address (the server's public address when it set one, because a link lists public → direct → onion); Onion address = the `<56>.onion` the link's onion service key derives (host only, no `:443`); Use Tor off.
- `no-onion` — The link carries no onion address: the onion field is empty and shows “Optional”.
- `field-error` — Connect was pressed with an edited value that is not an address: “This isn't a valid server address.” / “This isn't a valid onion address.” under that field; nothing is sent.
- `connecting` — Pairing under way: a spinner inside Connect; the fields, the checkbox, the back arrow and Cancel are disabled, and system back does nothing.
- `failed` — One line in the `error` colour under Connect says why (see Behavior); the fields keep what they hold.
- `waiting` — The link is an invite, and the server holds its request until the device that issued it answers: the fields give way to the same title, a centred spinner and “Waiting for approval on your other device” (titleMedium, centred, a live region); the only action left is “Cancel” (full-width text button). The back arrow stays visible and does nothing; system back does nothing.
- `cancelling` — Cancel pressed during the wait, the withdrawal on its way: Cancel disabled. An Allow that reached the server first still pairs.
- `declined` — The other device answered Deny: back to the form, and under Connect, in the `error` colour: “Your other device declined this request.”
- `no-answer` — The request ran out its ten minutes unanswered (the other device closed or offline; there are no notifications): back to the form with the expired-link line, “This link has expired. Ask for a new one.”
- `resumed` — The app was closed during the wait and opened again within its time: Login (2.1) opens this screen at once with the fields and Use Tor as they were, and the screen presents the same link again at once - the server knows it as the same request and answers with where it stands.

## Behavior
- The format check runs on Connect, over what was EDITED only: a value equal to the link's own passes as it is. Server address — `host:port`: an IPv4 address, an IPv6 address in brackets or a DNS name, port 1–65535, never an onion name. Onion address — a version-3 address: 56 base32 characters and `.onion`, any case, with or without `:443`, whose version byte and checksum hold (the checksum through the app's Tor module). Once shown, a field error follows the typing live.
- Connect pairs with what the screen shows. The device tries directly first — the link's direct addresses and the one in the field — and through Tor only when Use Tor is ticked and an onion address is known. The same holds for the very first device of a server (by a machine link) as for any later one.
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
- The wait (feature 046). A cause the path selector finds while the screen waits is not shown - the request is already on the server; a wait that ends because the connection was refused for good says why under Connect, like any failed attempt.
- Cancel during the wait withdraws the request: the token is spent, the other device stops being asked, and the screen closes back to Login (2.1) with nothing to explain. An Allow pressed afterwards does nothing.
- The wait survives a restart: while it lasts, the link, the fields and Use Tor are kept in secure storage with this device's own deadline - the invite's ten minutes and half a minute more, counted from the first “waiting” answer by the device's own clock. Closing the app does not withdraw the request.
- The wait survives a broken connection: the outcome arrives as an event that does not survive a disconnect, so the device presents the same link again on every new connection and at its own deadline, and the server answers with the outcome it recorded. At its deadline the device withdraws a request that still waits.

## Navigation
- Arrives from Login (2.1): Sign in on a pasted link, or a scan on QR scan (2.2), which hands the link to 2.1.
- Back arrow / Cancel / system back → Login (2.1), with the link still in its field. Not while connecting.
- Paired → Set username (2.3) when the pairing created the person (a machine link on a server with nobody yet), else Chats (5.1) — a machine link joining the person, or an invite once allowed — by the app-state spine, not by this screen.
- Cancel during the wait → Login (2.1), the screen closed.
- Arrives at once from Login (2.1) for a wait the app was closed in (`resumed`).

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
- Waiting: Waiting for approval on your other device
- Declined: Your other device declined this request.

## Design-system components
- AppBar (back, wordmark, splash hairline)
- TextField (outlined, single-line) ×2 — the same pair as Connection (7.10)
- CheckboxListTile
- FilledButton (pill, loading)
- TextButton
- AppSpinnerWidget (the wait)

---
Behaviour spec only: this screen has no live design in `index.html`. Locked by the goldens `connect_page`, `connect_page_no_onion`, `connect_page_field_error`, `connect_page_reason`, `connect_page_waiting` and `connect_page_declined`, at both widths.
