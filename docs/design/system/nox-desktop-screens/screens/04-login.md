# 03 · Login

> ⚠️ **Feature 032:** the field is the pairing link, not an identifier. Sign-in by identifier no longer exists — the device proves possession of a key that never leaves it. Refusals stay distinguishable: unreadable link, expired token, rejected token.

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
- `error-server` — Wrong server
- `error-home-only` — Home network only
- `error-net` — Network error

## Behavior
- Same field rules as mobile 2.1 (mono, multiline, paste, validation, loading), re-laid into a centered card.
- Empty → Sign in disabled. Submitting → button spinner. Format/network errors → inline errorText.
- Wrong server (036, narrowed by 040): a version-2 link parsed, and the server behind its ONION address presented a key the link did not name. Inline errorText “This server doesn't match its link”. Its own string because the next action differs from both of the others: not “scan it again”, not “check your connection”. There is no relationship with a server here yet, so the text names the LINK rather than a pairing that never happened.
- Home network only (040): a version-1 link whose server did not answer, or answered at the link's address with another key. Inline errorText “Couldn't reach your server. Pairing works on your home network.” - away from home such a link has no road to its server but the direct one.

## Navigation
- Success → Set username (03) or Chats (01).
- Scan QR → QR scan (03).

## Copy (EN)
- Label: Your ID
- Primary: Sign in
- Secondary: Scan QR
- Errors: Invalid identifier · Network error. Try again. · This server doesn't match its link · Couldn't reach your server. Pairing works on your home network.

## Design-system components
- DesktopWindow + TitleBar
- OnboardCard
- TextField (mono, multiline)
- FilledButton (loading)
- TextButton

---
Live design: open `index.html` → 03 Login (switch states with the chips). The desktop shell re-arranges the SAME widgets as mobile — only the wrapper differs.
