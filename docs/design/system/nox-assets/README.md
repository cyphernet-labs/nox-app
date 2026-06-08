# NOX — Assets package

Graphic resources for NOX: **icons**, **brand assets**, **illustrations**. Companion to
[`nox-handoff/`](../nox-handoff/README.md) (design tokens + Flutter code). Kept separate on
purpose — binaries and graphics version independently from the token/code handoff.

## Layout
```
nox-assets/
├── README.md
├── manifest.json              ← machine-readable index of every asset + status
├── index.html                 ← visual gallery (icon grid + brand + illustrations)
├── icons/
│   ├── icons.json             ← authoritative icon list (name → svg / Icons.* / Symbols.* / use)
│   ├── svg/                   ← 37 real SVG files (Material Symbols Rounded, currentColor)
│   └── README.md              ← install + style params
├── brand/
│   ├── logo.png               ← current logo (raster, splash)
│   ├── logo-reference.png     ← moodboard / palette source
│   └── README.md              ← wordmark + splash spec + pending vector/app-icon
└── illustrations/
    ├── empty-chats.svg        ← placeholder (5.1)
    ├── empty-messages.svg     ← placeholder (5.2)
    ├── empty-files.svg        ← placeholder (5.4)
    └── README.md              ← illustration spec + fallback icons
```

## What's here vs. what's referenced
- **Icons** — all stock **Material Symbols Rounded** (no custom glyphs). Ships the **real SVG files**
  (`icons/svg/`, 37 files, `currentColor`, Apache-2.0) plus `icons/icons.json` mapping each icon to
  its SVG, Flutter `Icons.*` / `Symbols.*` constant and usage. 33 unique ligatures, 38 references;
  outlined/filled via the FILL axis (`name.svg` / `name-fill.svg`).
- **Brand** — the actual `logo.png` + moodboard. The logo is a **raster placeholder**; the final
  vector SVG and app launcher icon are still to be ordered (flagged in `manifest.json`).
- **Illustrations** — the 3 empty-state illustrations don't exist yet, so these are labeled
  **placeholders** with the full spec to commission the real art. Screens fall back to icons meanwhile.

## Consuming it
`manifest.json` is the entry point — every asset has `path`, `format`, `status`
(`ready` / `placeholder` / `pending` / `reference-only`). A build script can read it to copy
ready assets and surface what's still outstanding. Colors referenced here (splash bg, QR) live as
brand-fixed tokens in `../nox-handoff/tokens/brand.tokens.json`.

Open `index.html` to browse everything visually.
