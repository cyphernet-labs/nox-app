# NOX — Desktop screens

Per-screen export of the **desktop** app (Windows / Linux / macOS, Material 3, canonical window
**1440×900**) for implementation. Each screen has a **detailed behavior spec** and a **live design**
rendered from the shared design system — not screenshots, not a copy: `index.html` mounts the real
components from `_src/`.

## Open `index.html`
A screen browser:
- **Left** — every screen, grouped (01 Chats · 02 Settings · 03 Onboarding · 04 Flows & dialogs · 05 States).
- **Center** — the selected screen rendered live in a 1440×900 window, scaled to fit. State chips above
  switch variants (selection / offline / dialog / drawer / …).
- **Right** — the spec: purpose, **how it adapts from mobile**, anatomy, behavior, navigation, copy, DS parts.
- **Top-right** — Light / Dark theme toggle.

## The key idea: same widgets, different shell
Desktop does **not** reimplement components — it re-arranges the same widgets the phone build uses:

| Mobile | Desktop |
|---|---|
| Bottom bar | NavigationRail (80) |
| Full-screen list + thread | two-pane **list-detail** |
| Bottom sheet | centered **Dialog** |
| Pushed File view | **lightbox** |
| Pushed Chat card / Files | right **drawer** |
| Pushed Create chat | **Dialog** |

## Structure
```
nox-desktop-screens/
├── index.html        ← screen browser (live design + spec + states)
├── specs.js          ← all screen specs as data (drives index.html)
├── screens/*.md      ← one detailed behavior spec per screen
├── _src/             ← snapshot of the design-system components (incl. desktop-shell/screens/flows)
└── assets/logo.png   ← splash / title-bar mark
```

## Screens
01 Chats (list-detail) · 02 Settings (list-detail) · 03 Onboarding (Splash · Login · Set username ·
QR scan) · 04 Flows & dialogs (Create chat · File view · Chat info / Files) · 05 Error.
Recoverable states (offline / loading / empty / search / snackbar) are shown as **states** of Chats
and Settings rather than separate screens — switch them with the chips.

## Linked to the design system
`_src/` is a **snapshot** of the live design-system components so this archive renders standalone.
The authoritative source is the project `src/`; the same widgets are specced for Flutter in
`nox-handoff/` (tokens, `flutter/widgets`, the adaptation table in `spec/components.md`).

> Icons render as glyphs in a real browser; flat screenshots may show Material Symbols ligatures as
> text — a capture artifact only.
