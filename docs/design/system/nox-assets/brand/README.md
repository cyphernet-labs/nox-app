# NOX — Brand assets

## logo.png
Current logo — full-color "mask" mark on dark. **200×200 PNG, opaque.** Used on the splash
(1.1) only, at 168×168 over `brand/canvasDark` (#0C2424), with the wordmark below.

> ⚠️ Raster placeholder for production. design-system.md §11 still requires a **final vector
> logo (SVG, full-color on dark)** and a **launcher app icon** — order these before release.

## logo-reference.png
Original moodboard / colour source (logo style + palette extraction, seed = teal #12B4B4).
Reference only — not a shipping asset.

## Wordmark "NOX"
| | |
|---|---|
| Text | `NOX` — always uppercase |
| Font | System sans (Roboto / SF Pro), **Bold 700** |
| Tracking | letter-spacing **+0.12em** |
| Color | splash: `brand/white` #FAFAFA on `brand/canvasDark`; AppBar: `colorScheme.onSurface` |

## Splash (brand-fixed, NOT themed)
Background is always `brand/canvasDark` #0C2424 (theming exception #1). Logo centered full-color,
wordmark below. One-shot reveal ~400ms (emphasized-decelerate). Cold start only.

## Pending brand assets (to order)
- Final logo **SVG** (full-color on dark).
- **App launcher icon** (from the logo).
- 3 **empty-state illustrations** — see `../illustrations/`.
