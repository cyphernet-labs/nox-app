# 2.1 · Login

> ⚠️ **Feature 032, link format from 044, Connect from 045:** the field is the pairing link `nox://pair/…` (version 3: the server's key, a one-time token and the server's addresses), not an identifier — the device proves possession of a key that never leaves it. This screen only READS the link: a link that will not parse and a link from a newer app are refused here, and every readable link goes on to Connect (2.4), which pairs and says whatever the server or the path answered.

> **Onboarding** · mobile (iOS / Android) · Material 3

**Purpose.** Take a pairing link — pasted or typed — or jump to QR scan, and hand a readable link to Connect (2.4).

## Anatomy
App bar (NOX wordmark + splash hairline). Multiline mono “Pairing link” field with a paste affordance (suffix). Pinned bottom: primary “Sign in”, secondary “Scan QR”.

## States
- `empty` — Empty
- `filled` — Filled
- `error-format` — Not a pairing link
- `error-newer` — Link from a newer app

## Behavior
- The field is monospace, multiline (min 120), and wraps break-all so a long link never overflows.
- Empty: Sign in disabled, paste icon at 38%. As soon as there is a value → enabled.
- Sign in (or Enter) reads the link on the device; nothing is dialled here and there is no spinner. A link that will not parse — not a link, truncated, or a format older than version 3: inline errorText “This isn't a pairing link”. A link whose version is above 3 — a newer server issued it: inline errorText “This link needs a newer version of NOX. Update the app and try again.”, its own string because the next action is to update the app rather than to scan again. Editing the field clears the error.
- A readable link opens Connect (2.4) at once. Whether the server answers, which path works and what the server says about the token are all said there, not here. Coming back from 2.4 keeps the link in the field.
- A scan on QR scan (2.2) lands on the same path: the link is put into the field and read exactly as if Sign in had been pressed.

## Navigation
- Readable link → Connect (2.4).
- Scan QR → QR scan (2.2).

## Copy (EN)
- Label: Pairing link
- Placeholder: Paste the link from your server
- Paste (tooltip): Paste
- Primary: Sign in
- Secondary: Scan QR
- Errors: “This isn't a pairing link” · “This link needs a newer version of NOX. Update the app and try again.”

## Design-system components
- AppBar (wordmark)
- TextField (outlined, mono, multiline)
- FilledButton
- TextButton
- Icon: content_paste

---
Live design: open `index.html` → 2.1 Login (switch states with the chips). Components are rendered from the shared design system (`_src/`).
