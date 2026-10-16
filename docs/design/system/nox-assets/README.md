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
│   ├── svg/                   ← 38 real SVG files (Material Symbols Rounded, currentColor)
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
  (`icons/svg/`, 38 files, `currentColor`, Apache-2.0) plus `icons/icons.json` mapping each icon to
  its SVG, Flutter `Icons.*` / `Symbols.*` constant and usage: 34 unique ligatures, 39 references,
  pointing at 36 of the 38 files (`flashlight_on.svg` and `send.svg` are not referenced — both are used
  filled). Outlined/filled via the FILL axis (`name.svg` / `name-fill.svg`). The `counts` block of
  `icons.json` says 34 / 39 / 36 (the files it points at); `manifest.json` still says 33 / 38 / 37.
- **In the app** — the shipped bundle `assets/svg/icons/` holds **60** SVGs: these 38 plus 22 glyphs
  the app added from the same `@material-symbols/svg-400` package — the 7.1 destinations `person`,
  `devices`, `palette`, `language`, `info`, `notifications` and `lan`, each outlined and filled, plus
  `description-fill`, `logout-fill`, `chevron_right`, `notifications_off`, `wifi_off`, `smartphone`,
  `play_arrow-fill` and `pause-fill`. **58** are exposed as `NoxIcons` getters; `flashlight_on.svg` and
  `send.svg` are bundled but unreferenced. `test/design/icons_resolution_test.dart` pins both counts.
- **Brand** — the actual `logo.png` + moodboard. The logo is a **raster placeholder**; the final
  vector SVG is still to be ordered (flagged in `manifest.json`). The launcher icons in
  `../nox-app-icons/` are built from this raster and installed in the app; the final set waits for the
  vector (`manifest.json` still lists the launcher icon as pending).
- **Illustrations** — the 3 empty-state SVGs are labeled **placeholders**, with the spec to commission
  real art. The app draws none of them: its empty state is the `NoxEmptyState` composition (a 56 glyph
  in a 132 box with two brand accents, `../nox-handoff-2/spec/primitives.md`).

## Consuming it
`manifest.json` is the entry point — every asset has `path`, `format`, `status`
(`ready` / `placeholder` / `pending` / `reference-only`). A build script can read it to copy
ready assets and surface what's still outstanding. Colors referenced here (splash bg, QR) live as
brand-fixed tokens in `../nox-handoff/tokens/brand.tokens.json`.

Open `index.html` to browse everything visually.
