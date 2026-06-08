# NOX — Flutter handoff package

Machine-readable export of the NOX design system (Material Design 3, light + dark) for
Flutter implementation. Everything here derives from the canonical source `src/tokens.jsx`
and the original specs in `uploads/`. Nothing is a screenshot — it is all parseable code/data.

## Layout

```
nox-handoff/
├── README.md                  ← you are here
├── tokens/                    ← W3C Design Tokens (DTCG) — the tool-agnostic source of truth
│   ├── $metadata.json         ← token-set load order
│   ├── brand.tokens.json      ← brand palette + brand-fixed colors (splash, QR)
│   ├── avatars.tokens.json    ← deterministic avatar-background palette
│   ├── color.light.tokens.json
│   ├── color.dark.tokens.json
│   ├── typography.tokens.json ← M3 type scale (composite typography tokens)
│   ├── spacing.tokens.json    ← 4dp grid
│   ├── shape.tokens.json      ← corner radii
│   ├── elevation.tokens.json  ← dp levels (+ light shadow approximation)
│   └── motion.tokens.json     ← durations + cubic-bezier easings
├── flutter/                   ← ready-to-drop Dart (Material Theme Builder style)
│   ├── nox_color_scheme.dart  ← ColorScheme light + dark
│   ├── nox_text_theme.dart    ← TextTheme
│   ├── nox_tokens.dart        ← spacing / radius / elevation / duration / easing consts
│   ├── nox_brand.dart         ← brand-fixed colors + avatar hash + initials
│   ├── nox_theme.dart         ← ThemeData wiring tokens into M3 components
│   └── README.md
└── spec/                      ← component & screen specs (widget mapping + token bindings)
    ├── components.md
    ├── screens.md
    └── icons.md
```

## Two ways to consume

**A — Generate from tokens (recommended for a token pipeline).**
The `tokens/*.tokens.json` files follow the [W3C Design Tokens Community Group format](https://tr.designtokens.org/format/).
Feed them to [Style Dictionary](https://styledictionary.com/), Tokens Studio, or a custom
generator to emit Dart/Kotlin/Swift/CSS. `$metadata.json` gives the load order; brand & avatar
sets are mode-independent, `color.light`/`color.dark` are the two themed sets.

**B — Drop in the Dart directly.**
`flutter/*.dart` is the same data already transformed to Flutter. Copy into `lib/theme/`,
add `Roboto` + `Roboto Mono` to `pubspec.yaml` (or rely on the platform default sans), and:

```dart
MaterialApp(
  theme: noxLightTheme,
  darkTheme: noxDarkTheme,
  themeMode: ThemeMode.system, // Settings 7.3
  home: const SplashScreen(),
);
```

The Dart and the JSON are generated from one source, so they never drift.

## Token format notes (for codegen authors)

- **Color** — hex string (`#RRGGBB`). → `Color(0xFF + RRGGBB)`.
- **dimension / duration** — `{ "value": N, "unit": "px"|"ms" }`. `px` ≡ Flutter logical px ≡ dp.
- **typography** (composite) — `fontFamily`, `fontSize` (dim), `fontWeight` (num), `letterSpacing`
  (dim, px), `lineHeight` (**unitless ratio** = M3 line-height ÷ font-size → Flutter `TextStyle.height`).
- **elevation** — `level/*` are dp **numbers** (pass to `Material`/`Card` elevation). `shadow/*`
  is the light-theme CSS approximation used in the HTML mockups **for non-Flutter consumers only** —
  in Flutter, elevation renders the tonal overlay + shadow automatically; do not hand-roll `BoxShadow`.
- **motion** — `cubicBezier` arrays map to `Cubic(...)`; see `nox_tokens.dart` for the named `Easing`/`Curves`.

## Source of truth & provenance

- Canonical token values: `src/tokens.jsx` (what all three HTML builds render from).
- Original written spec: `uploads/design-system.md` (§2 color, §3 type, §4 shape, §5 elevation,
  §6 spacing, §7 motion, §8 icons, §9 component tokens) and `uploads/overview.md` (UX rules).
- Where `tokens.jsx` and `design-system.md` differ on a few dark `surfaceContainer` values, the
  **`tokens.jsx` values are authoritative** here — that is the audited, implemented design.

## Visual reference (not part of this package)

For pixel-level reference of assembled screens, see the live builds in the project root:
`NOX - Mobile.html`, `NOX - Desktop.html`, `NOX - Design System.html`. They consume the same
`src/` widgets these tokens describe.

## Still to deliver (asset orders, per design-system.md §11)

Final logo SVG (full-color on dark) · app launcher icon · 3 empty-state illustrations
(chats / messages / files) · final `ColorScheme` tuning pass in Material Theme Builder.
