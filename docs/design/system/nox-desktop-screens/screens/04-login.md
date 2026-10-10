# 03 · Login

> ⚠️ **Feature 032, link format from 044, Connect from 045:** the field is the pairing link `nox://pair/…` (version 3: the server's key, a one-time token and the server's addresses), not an identifier — the device proves possession of a key that never leaves it. This screen only READS the link: a link that will not parse and a link from a newer app are refused here, and every readable link goes on to Connect (03), which pairs and says whatever the server or the path answered.

> **03 · Onboarding** · desktop (Windows / Linux / macOS) · Material 3 · window 1440×900

**Purpose.** Take a pairing link on desktop — a centered card on an empty window — and hand a readable link to Connect.

**Adaptation from mobile.** mobile full-screen form → centered card; identical field + button widgets

## Anatomy
Title bar (NOX — Sign in) + centered OnboardCard (440): logo + wordmark + brand hairline, mono multiline “Pairing link” field, “Sign in”, then “Scan QR” on macOS or “Use a QR image” on Windows and Linux.

## States
- `filled` — Filled
- `empty` — Empty
- `error-format` — Not a pairing link
- `error-newer` — Link from a newer app

## Behavior
- Same field rules as mobile 2.1 (mono, multiline, paste), re-laid into a centered card.
- Empty → Sign in disabled. Sign in reads the link on the device; nothing is dialled here and there is no spinner. A link that will not parse: inline errorText “This isn't a pairing link”. A link whose version is above 3: inline errorText “This link needs a newer version of NOX. Update the app and try again.” — the next action is to update the app, not to scan again.
- A readable link opens Connect (03) at once; the server's answer, the path and any refusal of the token are said there. Coming back from Connect keeps the link in the field.
- A wait for approval the app was closed in (feature 046) goes on: as this screen opens it hands that link to Connect with the settings it was set up with, and Connect presents it again at once. A wait whose time ran out is not offered.
- “Scan QR” exists only where the camera scanner does (macOS). On Windows and Linux “Use a QR image” stands in: pick an image, and a pairing link read from it takes exactly the path of a pasted one. An image with no pairing link in it → snackbar “Couldn't read a pairing link from that image.”, and nothing is submitted.

## Navigation
- Readable link → Connect (03).
- A wait the app was closed in, still within its time → Connect (03) at once, as it opens.
- Scan QR → QR scan (03) (macOS).
- Use a QR image → the system file picker (Windows, Linux).

## Copy (EN)
- Title bar: NOX — Sign in
- Label: Pairing link
- Placeholder: Paste the link from your server
- Primary: Sign in
- Secondary: Scan QR · Use a QR image
- Errors: This isn't a pairing link · This link needs a newer version of NOX. Update the app and try again.
- QR image without a link (snackbar): Couldn't read a pairing link from that image.

## Design-system components
- DesktopWindow + TitleBar
- OnboardCard
- TextField (mono, multiline)
- FilledButton
- TextButton

---
Live design: open `index.html` → 03 Login (switch states with the chips). The desktop shell re-arranges the SAME widgets as mobile — only the wrapper differs.
