# NOX — Icons

Every icon in NOX is a stock **Material Symbols Rounded** glyph — there are **no custom icons**.
This folder ships the **real SVG files** (`svg/`) plus the authoritative machine-readable
**list** (`icons.json`) mapping each icon to its SVG file, Flutter constant and usage.

## SVG files (`svg/`)
37 optimized SVGs from the official [`@material-symbols/svg-400`](https://www.npmjs.com/package/@material-symbols/svg-400)
package (Apache-2.0). Each: `width/height 48`, `viewBox="0 -960 960 960"`, single `<path fill="currentColor">`
— so they recolor via CSS `color` / SVG `fill` and drop straight into Flutter `SvgPicture.asset(...)`.

- Outlined (FILL 0): `svg/<name>.svg`
- Filled (FILL 1): `svg/<name>-fill.svg` (only for icons used filled: forum, settings, send, flashlight_on)

> Two names differ from the variable font: this svg package version has no `audiotrack` /
> `insert_drive_file`, so the visually identical **`music_note`** (audio) and **`draft`** (other file)
> are shipped instead. Stock Flutter still exposes `Icons.music_note` / `Icons.insert_drive_file`.

## Style
| Param | Value |
|---|---|
| Set | Material Symbols **Rounded** |
| Weight | 400 |
| Optical size | 24 |
| Grade | 0 |
| Default size | 24 dp (48–96 on 3.1 / 5.3) |

## Flutter
Use the SVGs via `flutter_svg`:
```dart
SvgPicture.asset('assets/icons/forum.svg',
  colorFilter: ColorFilter.mode(cs.onSurfaceVariant, BlendMode.srcIn));
```
or the font/package (no asset files needed):
```yaml
dependencies:
  material_symbols_icons: ^4.2.870
```
```dart
import 'package:material_symbols_icons/symbols.dart';
Icon(Symbols.forum, fill: 1, weight: 400, opticalSize: 24, grade: 0); // Rounded, filled
```
Or the built-in Material Icons: `Icon(Icons.forum)` / `Icon(Icons.forum_outlined)`.
`icons.json` lists the `svg` path, `Symbols.*` and `Icons.*` constant for each icon.

## `icons.json`
Grouped by role (navigation · actions · status · fileTypes · emptyStates · misc). Each entry:
`{ name, fill, svg, flutter, symbols, use }` — `name` is a valid base ligature, `svg` points to the
exact file in `svg/`, and outlined vs filled is the **FILL axis** (`fill` 0/1), since Material
Symbols has no `*_outlined` ligature. 33 unique ligatures, 38 references, 37 SVG files.
See `../index.html` for the visual grid (renders the actual SVGs).
