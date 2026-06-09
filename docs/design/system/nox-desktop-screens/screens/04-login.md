# 03 · Login

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
- `error-net` — Network error

## Behavior
- Same field rules as mobile 2.1 (mono, multiline, paste, validation, loading), re-laid into a centered card.
- Empty → Sign in disabled. Submitting → button spinner. Format/network errors → inline errorText.

## Navigation
- Success → Set username (03) or Chats (01).
- Scan QR → QR scan (03).

## Copy (EN)
- Label: Your ID
- Primary: Sign in
- Secondary: Scan QR
- Errors: Invalid identifier · Network error. Try again.

## Design-system components
- DesktopWindow + TitleBar
- OnboardCard
- TextField (mono, multiline)
- FilledButton (loading)
- TextButton

---
Live design: open `index.html` → 03 Login (switch states with the chips). The desktop shell re-arranges the SAME widgets as mobile — only the wrapper differs.
