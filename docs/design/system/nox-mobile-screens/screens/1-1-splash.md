# 1.1 · Splash

> **Onboarding** · mobile (iOS / Android) · Material 3

**Purpose.** Cold-start brand moment while the app resolves auth and decides where to route.

## Anatomy
Brand-fixed dark canvas (#0C2424, NOT themed). Centered logo (168) + NOX wordmark below (Bold 700, +0.12em, #FAFAFA).

## States
- `default` — Splash

## Behavior
- Shown only on cold start. One-shot reveal ~400ms (emphasized-decelerate); no looping.
- While visible the app opens its local data under this device's key and starts the connection; the first screen waits for that start and for the reveal, whichever ends later. A secure store that does not answer yet keeps the splash up and is asked again (after 2, 4, 8, 16, 30… s) - nothing is wiped for it; only on Android, a store that still fails at the fifth attempt (about half a minute) counts as a lost key.
- Background and wordmark colors are brand-fixed — they do NOT switch with light/dark theme.

## Navigation
- Paired, onboarding done → Chats shell (4.1 / 5.1).
- Paired, the name not yet set → Set username (2.3).
- Not paired → Login (2.1).
- Local data whose key is gone (a database the key does not open, or a database with no key) → that data is wiped, and Login (2.1).
- No route to Error (3.1): nothing at start-up ends on the error screen.

## Copy (EN)
- Wordmark: NOX

## Design-system components
- Brand: canvasDark, white
- Type: wordmark (Bold 700)
- Motion: splashIn 400ms

---
Live design: open `index.html` → 1.1 Splash (switch states with the chips). Components are rendered from the shared design system (`_src/`).
