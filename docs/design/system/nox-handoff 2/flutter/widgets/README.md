# NOX widgets → Flutter

Every design-system primitive in a form that maps 1:1 to Flutter — no mechanical conversion.

## Three coupled artifacts per widget
1. **Dart** (`*.dart` here) — hand-written, idiomatic Material 3 widgets that consume the theme
   (`../nox_theme.dart`, `../nox_tokens.dart`, `../nox_brand.dart`).
2. **Spec** (`../../spec/primitives.md`) — brief description, props/API, token bindings.
3. **Live gallery** (`preview.html`) — the real `src/` components rendered next to each widget's Dart.

## Dart files
| File | Widgets |
|---|---|
| `nox_primitives.dart` | `NoxIcon`, `NoxSpinner`, `NoxAvatar`, `NoxFileGlyph`, `NoxFileType` + `noxFileIcon`/`noxFileColor` |
| `nox_widgets.dart` | `NoxSearchBar`, `NoxChatListItem`, `NoxFileChip`, `NoxMessageBubble` (+`NoxMsgStatus`), `NoxComposer`, `NoxEmptyState`, `NoxSegmented` |
| `nox_scaffold.dart` | `NoxSplashHairline`, `NoxWordmark`, `NoxBottomBar`+`NoxCreateFab` (+`NoxTab`), `showNoxSnackBar`, `showNoxBanner` |

Stock-themed widgets (FilledButton, TextButton, IconButton, TextField, SegmentedButton, AlertDialog,
bottom sheet, Card) are **not** reimplemented — they're styled by `../nox_theme.dart`; usage is in `primitives.md`.

## Custom vs stock
A `custom` tag = a `Nox*` class here. A `stock` tag = plain Flutter widget + theme. The gallery and
spec mark each one.

## Dependencies
- `flutter/material.dart`
- [`material_symbols_icons`](https://pub.dev/packages/material_symbols_icons) for `Symbols.*` (Rounded).
- For empty-state / file icons rendered from SVG instead of the font: [`flutter_svg`](https://pub.dev/packages/flutter_svg) + the SVGs in `nox-assets/icons/svg`.

## `_src/`
Snapshot of the three `src/*.jsx` files (`tokens`, `m3`, `chats-parts`) the gallery renders from, so
`preview.html` is self-contained in this package. They are a **reference snapshot** of the live
design system — the authoritative source remains the project `src/`.
