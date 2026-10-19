# 3.1 · Error (universal)

> **Onboarding** · mobile (iOS / Android) · Material 3

**Purpose.** Reusable fatal / unexpected error state with a retry.

## Anatomy
Centered error glyph (onSurfaceVariant, 48–96) + title + message + primary “Try again”.

## States
- `blocking` — Blocking
- `embedded` — Embedded

## Behavior
- Blocking variant has NO back button: it is the last entry in the stack (e.g. onboarding could not be finished on 2.3), and on Android the system back minimizes the app. The splash never routes here.
- Embedded variant shows a back arrow (reached from within a flow).
- Props: icon, title, message, onRetry. Copy pattern: “Could not <verb>. Check your connection and try again.”

## Navigation
- Try again → re-runs the failed action.
- Embedded back → previous screen.
- Blocking, system back (Android) → minimizes the app.

## Copy (EN)
- Default title: Something went wrong
- Action: Try again

## Design-system components
- Icon: error_outline (80)
- Type: headlineSmall + bodyMedium
- FilledButton
- AppBar (embedded only)

---
Live design: open `index.html` → 3.1 Error (universal) (switch states with the chips). Components are rendered from the shared design system (`_src/`).
