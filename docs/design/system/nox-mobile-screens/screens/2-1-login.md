# 2.1 · Login

> ⚠️ **Feature 032:** the field is the pairing link, not an identifier. Sign-in by identifier no longer exists — the device proves possession of a key that never leaves it. Refusals stay distinguishable: unreadable link, expired token, rejected token.

> **Onboarding** · mobile (iOS / Android) · Material 3

**Purpose.** Sign in by pasting / typing an existing account ID, or jump to QR scan.

## Anatomy
App bar (NOX wordmark + splash hairline). Multiline mono ID field with a paste affordance (suffix). Pinned bottom: primary “Sign in”, secondary “Scan QR”.

## States
- `empty` — Empty
- `filled` — Filled
- `loading` — Submitting
- `error-format` — Format error
- `error-server` — Wrong server
- `error-net` — Network error

## Behavior
- ID field is monospace, multiline (min 120), wraps break-all so a long ID never overflows.
- Empty: Sign in disabled, paste icon at 38%. As soon as there is a value → enabled.
- Submitting: button shows an inline spinner (onPrimary); field + Scan QR disabled.
- Format error: inline errorText “Invalid identifier”. Per **FR-011 there is no client-side identifier validation** — this state is reached only by the server (a future 401-interceptor / sign-in rejection) or the dev outcome selector, never by a pre-submit local check.
- Network/5xx on submit: inline errorText “Could not sign in. Check your connection and try again.”
- Wrong server (036): the link parsed, and the machine at the address it carries presented a key the link did not name. Inline errorText “This server doesn't match its link”. Its own string because the next action differs again: not “scan it again” and not “check your connection”. There is no relationship with a server here yet, so the text names the LINK rather than a pairing that never happened. Reached from the session phase, not from the sign-in result: the key is checked during the handshake, before anything is sent, so the call itself can only report that there was no channel.

## Navigation
- Success → Set username (2.3) for new IDs, else Chats (5.1).
- Scan QR → QR scan (2.2).
- Fatal/unexpected → Error (3.1).

## Copy (EN)
- Label: Your ID
- Placeholder: Paste or enter your ID
- Primary: Sign in
- Secondary: Scan QR
- Errors: “Invalid identifier” · “Could not sign in. Check your connection and try again.” · “This server doesn't match its link”

## Design-system components
- AppBar (wordmark)
- TextField (outlined, mono, multiline)
- FilledButton (loading)
- TextButton
- Icon: content_paste

---
Live design: open `index.html` → 2.1 Login (switch states with the chips). Components are rendered from the shared design system (`_src/`).
