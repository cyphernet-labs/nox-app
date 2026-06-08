# NOX — Mobile screens

Per-screen export of the **mobile** app (iOS / Android, Material 3) for implementation. Each screen
has a **detailed behavior spec** and a **live design** rendered from the shared design system — not
screenshots, and not a copy: `index.html` mounts the real components from `_src/`.

## Open `index.html`
A screen browser:
- **Left** — every screen, grouped (Onboarding · Shell & Chats · Settings).
- **Center** — the selected screen rendered live in a phone frame, scaled to fit. State chips above
  switch variants (empty / loading / error / offline / …).
- **Right** — the screen's spec: purpose, anatomy, behavior, navigation, copy, design-system parts.
- **Top-right** — Light / Dark theme toggle (applies the real M3 ColorScheme to every screen).

## Structure
```
nox-mobile-screens/
├── index.html        ← screen browser (live design + spec + states)
├── specs.js          ← all screen specs as data (drives index.html)
├── screens/*.md      ← one detailed behavior spec per screen (read these for dev)
├── _src/             ← snapshot of the design-system components the screens render from
└── assets/logo.png   ← splash / brand mark
```

## Screens
Onboarding — 1.1 Splash · 2.1 Login · 2.2 QR scan (+ permission) · 2.3 Set username · 3.1 Error.
Shell & Chats — 4.1 Navigation shell · 5.1 Chats list · 5.2 Chat thread · 5.3 File view · 5.4 Chat card · 6.1 Create chat.
Settings — 7.1 Settings root · 7.2 Notifications · 7.3 Appearance · 7.4 Language · 7.6 Terms · 7.7 About.

Each `.md` lists the screen's states, behavior, navigation, EN copy and the design-system components
it uses. The same components are specced for Flutter in the handoff package (`nox-handoff/`):
tokens → `nox-handoff/tokens`, widgets → `nox-handoff/flutter/widgets`, icons → `nox-assets/icons`.

## Linked to the design system
`_src/` is a **snapshot** of the live design-system components (`tokens`, `m3`, `chats-parts`,
`screens-*`) so this archive renders standalone. The authoritative source remains the project `src/`;
editing a widget there updates the design system, the Flutter handoff and these screens alike.

> The icon font renders as glyphs in a real browser; in flat screenshots Material Symbols ligatures
> may appear as text — a capture artifact only.
