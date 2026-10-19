# NOX — Assets package

Graphic resources for NOX: **icons**, **brand assets** and the corpus's **empty-state sketches**. Companion to
[`nox-handoff/`](../nox-handoff/README.md) (design tokens + Flutter code). Kept separate on
purpose — binaries and graphics version independently from the token/code handoff.

## Layout
```
nox-assets/
├── README.md
├── manifest.json              ← machine-readable index of every asset + status
├── index.html                 ← visual gallery (icon grid + brand + empty-state sketches)
├── icons/
│   ├── icons.json             ← authoritative icon list (name → svg / Icons.* / Symbols.* / use)
│   ├── svg/                   ← 38 real SVG files (Material Symbols Rounded, currentColor)
│   └── README.md              ← install + style params
├── brand/
│   ├── logo.png               ← current logo (raster, splash)
│   ├── logo-reference.png     ← moodboard / palette source
│   └── README.md              ← wordmark + splash spec + pending vector logo
└── illustrations/
    ├── empty-chats.svg        ← corpus sketch (5.1), not shipped
    ├── empty-messages.svg     ← corpus sketch (5.2), not shipped
    ├── empty-files.svg        ← corpus sketch (5.4), not shipped
    └── README.md              ← what the sketches are + the glyphs the app draws
```

## What's here vs. what's referenced
- **Icons** — all stock **Material Symbols Rounded** (no custom glyphs). Ships the **real SVG files**
  (`icons/svg/`, 38 files, `currentColor`, Apache-2.0) plus `icons/icons.json` mapping each icon to
  its SVG, Flutter `Icons.*` / `Symbols.*` constant and usage: 34 unique ligatures, 39 references,
  pointing at 36 of the 38 files (`flashlight_on.svg` and `send.svg` are not referenced — both are used
  filled). Outlined/filled via the FILL axis (`name.svg` / `name-fill.svg`). The `counts` block of
  `icons.json` says 34 / 39 / 36 (the files it points at); `manifest.json` carries the same 34 / 39,
  with `svgFiles` 38 and `svgFilesReferenced` 36.
- **In the app** — the shipped bundle `assets/svg/icons/` holds **60** SVGs: these 38 plus 22 glyphs
  the app added from the same `@material-symbols/svg-400` package — the 7.1 destinations `person`,
  `devices`, `palette`, `language`, `info`, `notifications` and `lan`, each outlined and filled, plus
  `description-fill`, `logout-fill`, `chevron_right`, `notifications_off`, `wifi_off`, `smartphone`,
  `play_arrow-fill` and `pause-fill`. **58** are exposed as `NoxIcons` getters; `flashlight_on.svg` and
  `send.svg` are bundled but unreferenced. `test/design/icons_resolution_test.dart` pins both counts.
- **Brand** — the actual `logo.png` + moodboard. The logo is a **raster placeholder**; the final
  vector SVG is still to be ordered (flagged in `manifest.json`). The launcher icons in
  `../nox-app-icons/` are built from this raster and installed in the app; the final set waits for the
  vector (`manifest.json` marks the launcher icon `placeholder-raster`).
- **Empty-state sketches** — the 3 SVGs in `illustrations/` are sketches of the corpus only: no
  illustration is ordered, and none ships in the app. The art of an empty state is the `NoxEmptyState`
  composition (`AppEmptyContentWidget` in the app): a 56 glyph in a 132 box with two brand accents
  (`design-system.md` §10, `../nox-handoff-2/spec/primitives.md`).

## Consuming it
`manifest.json` is the entry point — every asset carries a `status` (`ready` / `placeholder-raster` /
`reference-only` / `spec-only` / `corpus-sketch`), and the orders still outstanding are listed under
`pending`. A build script can read it to copy ready assets and surface what's still outstanding.
Colors referenced here (splash bg, QR) live as brand-fixed tokens in
`../nox-handoff/tokens/brand.tokens.json`.

Open `index.html` to browse everything visually.
