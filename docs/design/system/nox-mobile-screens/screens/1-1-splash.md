# 1.1 · Splash

> **Onboarding** · mobile (iOS / Android) · Material 3

**Purpose.** Cold-start brand moment while the app resolves auth and decides where to route.

## Anatomy
Brand-fixed dark canvas (#0C2424, NOT themed). Centered logo (168) + NOX wordmark below (Bold 700, +0.12em, #FAFAFA).

## States
- `default` — Splash

## Behavior
- Shown only on cold start. One-shot reveal ~400ms (emphasized-decelerate); no looping.
- While visible the app restores the stored ID and checks session validity.
- Background and wordmark colors are brand-fixed — they do NOT switch with light/dark theme.

## Navigation
- Has stored, valid ID → Chats shell (4.1 / 5.1).
- No ID → Login (2.1).
- Resolution error → Error (3.1, blocking).

## Copy (EN)
- Wordmark: NOX

## Design-system components
- Brand: canvasDark, white
- Type: wordmark (Bold 700)
- Motion: splashIn 400ms

---
Live design: open `index.html` → 1.1 Splash (switch states with the chips). Components are rendered from the shared design system (`_src/`).
