# 2.1 · Login

> **Onboarding** · mobile (iOS / Android) · Material 3

**Purpose.** Sign in by pasting / typing an existing account ID, or jump to QR scan.

## Anatomy
App bar (NOX wordmark + splash hairline). Multiline mono ID field with a paste affordance (suffix). Pinned bottom: primary “Sign in”, secondary “Scan QR”.

## States
- `empty` — Empty
- `filled` — Filled
- `loading` — Submitting
- `error-format` — Format error
- `error-net` — Network error

## Behavior
- ID field is monospace, multiline (min 120), wraps break-all so a long ID never overflows.
- Empty: Sign in disabled, paste icon at 38%. As soon as there is a value → enabled.
- Submitting: button shows an inline spinner (onPrimary); field + Scan QR disabled.
- Format error: inline errorText “Invalid identifier”. Per **FR-011 there is no client-side identifier validation** — this state is reached only by the server (a future 401-interceptor / sign-in rejection) or the dev outcome selector, never by a pre-submit local check.
- Network/5xx on submit: inline errorText “Could not sign in. Check your connection and try again.”

## Navigation
- Success → Set username (2.3) for new IDs, else Chats (5.1).
- Scan QR → QR scan (2.2).
- Fatal/unexpected → Error (3.1).

## Copy (EN)
- Label: Your ID
- Placeholder: Paste or enter your ID
- Primary: Sign in
- Secondary: Scan QR
- Errors: “Invalid identifier” · “Could not sign in. Check your connection and try again.”

## Design-system components
- AppBar (wordmark)
- TextField (outlined, mono, multiline)
- FilledButton (loading)
- TextButton
- Icon: content_paste

---
Live design: open `index.html` → 2.1 Login (switch states with the chips). Components are rendered from the shared design system (`_src/`).
