# NOX — Brand assets

## logo.png
Current logo — full-color "mask" mark on dark. **200×200 PNG, opaque.** On the splash (1.1) at
168×168 over `brand/canvasDark` (#0C2424), with the wordmark below; on desktop also in the onboarding
card and as the window title-bar mark. The app's copy is `assets/png/logo.png` (byte-identical).

> ⚠️ Raster placeholder for production. design-system.md §11 still requires a **final vector
> logo (SVG, full-color on dark)** — order it before release; the final launcher icon set and its
> monochrome master come from it. The launcher icons the app ships (`../../nox-app-icons/`) are built
> from this raster.

## logo-reference.png
Original moodboard / colour source (logo style + palette extraction, seed = teal #12B4B4).
Reference only — not a shipping asset.

## Wordmark "NOX"
| | |
|---|---|
| Text | `NOX` — always uppercase |
| Font | Roboto **Bold 700**, bundled with the app on every platform |
| Tracking | letter-spacing **+0.12em** |
| Color | splash: `brand/white` #FAFAFA on `brand/canvasDark`; AppBar: `colorScheme.onSurface` |

## Splash (brand-fixed, NOT themed)
Background is always `brand/canvasDark` #0C2424 (theming exception #1). Logo centered full-color,
wordmark below. One-shot reveal ~400ms (emphasized-decelerate). Cold start only.

## Pending brand assets (to order)
- Final logo **SVG** (full-color on dark).
- **App launcher icon** from the final vector logo (a set from the raster ships meanwhile, `../../nox-app-icons/`).

No empty-state illustration is ordered: the art of an empty state is the `NoxEmptyState` composition
(design-system.md §10), and `../illustrations/` holds only sketches of the corpus.
