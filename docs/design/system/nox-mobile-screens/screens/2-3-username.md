# 2.3 · Set username

> **Onboarding** · mobile (iOS / Android) · Material 3

**Purpose.** Pick the display name others see (optional — server pre-assigns one).

## Anatomy
App bar (wordmark). Name field with counter N/32 + helper. Pinned bottom: primary “Done”, secondary “Skip”.

## States
- `prefilled` — Prefilled
- `checking` — Checking
- `taken` — Taken
- `empty` — Empty
- `invalid-charset` — Out-of-charset

## Behavior
- Pre-filled with the server default handle (e.g. User1234); user may keep, edit or skip.
- Max 32 chars; counter updates live. Charset for username is restricted ([A-Za-z0-9._-]); the client **validates immediately and shows an errorText** for an out-of-charset name (a deliberate validate-with-feedback choice — the user sees why a character was rejected — rather than silently filtering input).
- Checking: trailing spinner while uniqueness is verified.
- Taken: errorText “This name is taken”; Done disabled until resolved. Empty: Done disabled.
- Out-of-charset: errorText “Contains invalid characters (allowed: letters, digits, - _ .)”; Done disabled until resolved.

## Navigation
- Done / Skip → Chats shell (5.1).

## Copy (EN)
- Label: Name
- Placeholder: How others will see you
- Counter: N/32
- Helper: Others see this name. You can change it now or later in Settings.
- Error (taken): This name is taken
- Error (charset): Contains invalid characters (allowed: letters, digits, - _ .)
- Primary: Done
- Secondary: Skip

## Design-system components
- AppBar (wordmark)
- TextField (counter, helper, spinner suffix)
- FilledButton
- TextButton

---
Live design: open `index.html` → 2.3 Set username (switch states with the chips). Components are rendered from the shared design system (`_src/`).
