# 03 · Connect

> **03 · Onboarding** · desktop (Windows / Linux / macOS) · Material 3 · window 1440×900 · new in feature 045 · the wait for approval since feature 046

**Purpose.** Show where a pairing link leads before the device pairs, let the person change it, and pair — a centred card on an empty window, like Login.

**Adaptation from mobile.** mobile full-screen form with a back arrow (2.4) → centred onboarding card under the window title bar; identical fields, checkbox and buttons; `Cancel` is the only way back

## Anatomy
Title bar (NOX — Sign in) with the brand gradient line under it + centred OnboardCard (440): logo, NOX wordmark, short gradient pill; then the title “Connect to your server”, the “Server address” field, the “Onion address” field (“Optional” while empty), the “Use Tor” checkbox row with its caption, “Connect”, the reason line when there is one, and “Cancel”. No back arrow. The card sits in a scroll view: at 1280×800 with a reason line it is slightly taller than the window and the window scrolls; at the canonical 1440×900 it fits.

## States
- `filled` — Filled from the link: the link's first direct address (the server's public address when it set one) and the onion address its onion service key derives; Use Tor off.
- `no-onion` — The link carries no onion address: the onion field is empty and shows “Optional”.
- `field-error` — Connect pressed with an edited value that is not an address: the error under that field; nothing is sent.
- `connecting` — Spinner inside Connect; fields, checkbox and Cancel disabled.
- `failed` — One line in the `error` colour under Connect says why.
- `waiting` — An invite whose request waits for the device that issued it: inside the same card the fields give way to the title, a centred spinner and “Waiting for approval on your other device” (a live region); “Cancel” is the only action.
- `cancelling` — Cancel pressed during the wait: Cancel disabled while the withdrawal goes out. An Allow that got there first still pairs.
- `declined` — The other device answered Deny: the form again, and “Your other device declined this request.” under Connect.
- `no-answer` — The request ran out its ten minutes unanswered: the form again with “This link has expired. Ask for a new one.”
- `resumed` — A wait the app was closed in, still within its time: Login opens this screen at once, which presents the same link again with the same settings.

## Behavior
- Same rules as mobile 2.4. The format check covers what was edited — `host:port` for the server address (IPv4, bracketed IPv6 or a DNS name; port 1–65535; never an onion name), a version-3 onion address with a valid version byte and checksum — and a value equal to the link's own passes as it is.
- Connect pairs directly first, and through Tor only when Use Tor is ticked and an onion address is known, the first device of a server included. The token goes out only where the server proved the key the link names; the server key itself is never shown.
- A cause found during the attempt shows under Connect at once (a live region). Failed: one of the five causes (“No server answers at this onion address. Check the address and that Tor is running on the server.” · “Your server isn't answering through Tor right now. Check that it is running.” · “This onion address belongs to a different server.” · “Can't connect to the Tor network. Check your internet connection.” · “Can't reach the server directly. Turn on Use Tor to connect through Tor.”), else “Could not sign in. Check your connection and try again.”; a refused token says “This link has expired. Ask for a new one.” or “This link can't be used. Ask for a new one.” An onion address the Tor module refused as not version 3 is said at the onion field instead.
- Any edit — a field or the checkbox — clears the line.
- Paired: what differs from the link is stored as the person's own edit and Use Tor as ticked; both stay editable in Settings → Connection (12).
- The wait, as on mobile 2.4 (feature 046): a machine link pairs at once, an invite only after Allow on the device that issued it (04 · Pair request). Cancel withdraws the request and closes the card back to Login. Closing the app does not withdraw it: within the device's own deadline - the invite's ten minutes and half a minute more, from the first “waiting” answer - the wait goes on after a restart, and the same link is presented again on every new connection, since the outcome event does not survive a disconnect.

## Navigation
- Arrives from Login (03): Sign in on a pasted link; on macOS also a scan on QR scan (03); on Windows and Linux also Use a QR image.
- Cancel → Login (03), the link still in its field. Not while connecting. During the wait Cancel withdraws the request and closes the card.
- Paired → Set username (03) when a machine link created the person, else Chats (01).
- Arrives at once from Login (03) for a wait the app was closed in (`resumed`).

## Copy (EN)
- Title bar: NOX — Sign in
- Title: Connect to your server
- Fields: Server address · Onion address
- Onion helper (empty field): Optional
- Checkbox: Use Tor
- Caption: NOX uses Tor only when it can't reach your server directly.
- Primary: Connect
- Secondary: Cancel
- Field errors: This isn't a valid server address. · This isn't a valid onion address.
- Reasons: the five causes above · Could not sign in. Check your connection and try again. · This link has expired. Ask for a new one. · This link can't be used. Ask for a new one.
- Waiting: Waiting for approval on your other device
- Declined: Your other device declined this request.

## Design-system components
- DesktopWindow + TitleBar
- OnboardCard
- TextField (outlined, single-line) ×2
- CheckboxListTile
- FilledButton (loading)
- TextButton
- AppSpinnerWidget (the wait)

---
Behaviour spec only: this screen has no live design in `index.html`. Locked by the desktop goldens `connect_page_desktop`, `connect_page_no_onion_desktop`, `connect_page_field_error_desktop`, `connect_page_reason_desktop`, `connect_page_waiting_desktop` and `connect_page_declined_desktop`.
