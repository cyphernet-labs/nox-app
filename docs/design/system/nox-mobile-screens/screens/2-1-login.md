# 2.1 · Login

> ⚠️ **Feature 032, link format from 044:** the field is the pairing link `nox://pair/…` (version 3: the server's key, a one-time token and the server's addresses), not an identifier. Sign-in by identifier no longer exists — the device proves possession of a key that never leaves it. Refusals stay distinguishable: unreadable link, link from a newer app, expired token, rejected token.

> **Onboarding** · mobile (iOS / Android) · Material 3

**Purpose.** Sign in by pasting / typing an existing account ID, or jump to QR scan.

## Anatomy
App bar (NOX wordmark + splash hairline). Multiline mono ID field with a paste affordance (suffix). Pinned bottom: primary “Sign in”, secondary “Scan QR”.

## States
- `empty` — Empty
- `filled` — Filled
- `loading` — Submitting
- `error-format` — Format error
- `error-newer` — Link from a newer app
- `error-server` — Wrong server
- `error-home-only` — Home network only
- `error-net` — Network error

## Behavior
- ID field is monospace, multiline (min 120), wraps break-all so a long ID never overflows.
- Empty: Sign in disabled, paste icon at 38%. As soon as there is a value → enabled.
- Submitting: button shows an inline spinner (onPrimary); field + Scan QR disabled.
- Format error: inline errorText “Invalid identifier”. Per **FR-011 there is no client-side identifier validation** — this state is reached only by the server (a future 401-interceptor / sign-in rejection) or the dev outcome selector, never by a pre-submit local check.
- Network/5xx on submit: inline errorText “Could not sign in. Check your connection and try again.”
- Link from a newer app (044): the link parsed up to its version byte and the version is above 3 — a newer server issued it. Inline errorText “This link needs a newer version of NOX. Update the app and try again.” Nothing was dialled. Its own string because the next action is to update the app, not to rescan or check the connection.
- Wrong server (036, narrowed by 040): the server behind the link's ONION address presented a key the link did not name (checked by the Eidolon exchange on the connection, before anything is sent). Inline errorText “This server doesn't match its link”. Until 045 pairing never goes over onion, so this state does not occur in the real flow. Its own string because the next action differs again: not “scan it again” and not “check your connection”. There is no relationship with a server here yet, so the text names the LINK rather than a pairing that never happened.
- Home network only (040, every link since 044): the server did not answer at any direct address of the link, or answered there with another key. Inline errorText “Couldn't reach your server. Pairing works on your home network.” Pairing goes over the direct addresses only — the onion service opens only for an already paired device's access key (until 045) — so away from home that is the expected outcome rather than a fault.

## Navigation
- Success → Set username (2.3) for new IDs, else Chats (5.1).
- Scan QR → QR scan (2.2).
- Fatal/unexpected → Error (3.1).

## Copy (EN)
- Label: Your ID
- Placeholder: Paste or enter your ID
- Primary: Sign in
- Secondary: Scan QR
- Errors: “This isn't a pairing link” · “This link needs a newer version of NOX. Update the app and try again.” · “Could not sign in. Check your connection and try again.” · “This server doesn't match its link” · “Couldn't reach your server. Pairing works on your home network.”

## Design-system components
- AppBar (wordmark)
- TextField (outlined, mono, multiline)
- FilledButton (loading)
- TextButton
- Icon: content_paste

---
Live design: open `index.html` → 2.1 Login (switch states with the chips). Components are rendered from the shared design system (`_src/`).
