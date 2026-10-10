# 03 · Login

> ⚠️ **Feature 032, link format from 044:** the field is the pairing link `nox://pair/…` (version 3: the server's key, a one-time token and the server's addresses), not an identifier. Sign-in by identifier no longer exists — the device proves possession of a key that never leaves it. Refusals stay distinguishable: unreadable link, link from a newer app, expired token, rejected token.

> **03 · Onboarding** · desktop (Windows / Linux / macOS) · Material 3 · window 1440×900

**Purpose.** Sign in with an ID on desktop — a centered card on an empty window.

**Adaptation from mobile.** mobile full-screen form → centered card; identical field + button widgets

## Anatomy
Title bar (NOX · Sign in) + centered OnboardCard (440): logo + wordmark + brand hairline, mono multiline ID field, “Sign in”, “Scan QR”.

## States
- `filled` — Filled
- `empty` — Empty
- `loading` — Submitting
- `error-format` — Format error
- `error-newer` — Link from a newer app
- `error-server` — Wrong server
- `error-home-only` — Home network only
- `error-net` — Network error

## Behavior
- Same field rules as mobile 2.1 (mono, multiline, paste, validation, loading), re-laid into a centered card.
- Empty → Sign in disabled. Submitting → button spinner. Format/network errors → inline errorText.
- Link from a newer app (044): the link parsed up to its version byte and the version is above 3 — a newer server issued it. Inline errorText “This link needs a newer version of NOX. Update the app and try again.” Nothing was dialled. Its own string because the next action is to update the app, not to rescan or check the connection.
- Wrong server (036, narrowed by 040): the server behind the link's ONION address presented a key the link did not name (checked by the Eidolon exchange on the connection, before anything is sent). Inline errorText “This server doesn't match its link”. Until 045 pairing never goes over onion, so this state does not occur in the real flow. Its own string because the next action differs again: not “scan it again” and not “check your connection”. There is no relationship with a server here yet, so the text names the LINK rather than a pairing that never happened.
- Home network only (040, every link since 044): the server did not answer at any direct address of the link, or answered there with another key. Inline errorText “Couldn't reach your server. Pairing works on your home network.” Pairing goes over the direct addresses only — the onion service opens only for an already paired device's access key (until 045) — so away from home that is the expected outcome rather than a fault.

## Navigation
- Success → Set username (03) or Chats (01).
- Scan QR → QR scan (03).

## Copy (EN)
- Label: Your ID
- Primary: Sign in
- Secondary: Scan QR
- Errors: This isn't a pairing link · This link needs a newer version of NOX. Update the app and try again. · Network error. Try again. · This server doesn't match its link · Couldn't reach your server. Pairing works on your home network.

## Design-system components
- DesktopWindow + TitleBar
- OnboardCard
- TextField (mono, multiline)
- FilledButton (loading)
- TextButton

---
Live design: open `index.html` → 03 Login (switch states with the chips). The desktop shell re-arranges the SAME widgets as mobile — only the wrapper differs.
