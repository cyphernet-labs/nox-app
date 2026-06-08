# NOX — Component spec (M3 widget → token bindings)

Each component maps to a stock Material 3 Flutter widget (minimal customization), bound to the
tokens in `../tokens/`. Color roles are `ColorScheme` roles unless marked **brand-fixed**.
Most theming is already applied in `flutter/nox_theme.dart`; this doc is the per-component reference.

> Icon set: **Material Symbols Rounded** (weight 400, optical 24, grade 0). In Flutter use
> `Icons.*` or the `material_symbols_icons` package (`Symbols.*`). Names listed in `icons.md`.

---

## Buttons

| Component | Flutter widget | Bindings |
|---|---|---|
| Primary | `FilledButton` | bg `primary`, fg `onPrimary`, shape `full` (StadiumBorder), text `labelLarge`. Disabled: bg `onSurface`@12%, text `onSurface`@38%. Min height 48. |
| Secondary | `TextButton` | text `primary`, shape `full`, `labelLarge`. |
| Loading | `FilledButton` + `CircularProgressIndicator` | spinner `onPrimary` (load-bearing on `primary` bg). |
| Icon action | `IconButton` | icon `onSurfaceVariant` (or `primary` when active), tap-target 48×48. |

## Text input

| Component | Flutter widget | Bindings |
|---|---|---|
| Text field | `TextField` (outlined) | shape `xs`, border `outline` → focus `primary` (2dp) → error `error`. Text `onSurface` `bodyLarge`. Helper/counter `onSurfaceVariant` `bodyMedium`. |
| ID field (7.1) | `TextField` mono | family **mono**, `bodyLarge` metrics, value wraps `break-all`, color `onSurfaceVariant`. |
| Availability check | `TextField` + suffix `CircularProgressIndicator` | suffix spinner `onSurfaceVariant`. |

## Search

| Component | Flutter widget | Bindings |
|---|---|---|
| Search bar | `SearchBar` | bg `surfaceContainerHigh`, shape `full`, elevation 2, text `onSurface`, hint `onSurfaceVariant`. |

## Selection controls

| Component | Flutter widget | Bindings |
|---|---|---|
| Segmented | `SegmentedButton` | selected `secondaryContainer`/`onSecondaryContainer`, unselected `onSurface`, outline `outline`, shape `s`. |
| Switch | `SwitchListTile` | M3 default (on: track/thumb `primary`; off: `outline`/`surfaceVariant`), label `onSurface`. |
| Radio | `RadioListTile` | selected `primary`, unselected `onSurfaceVariant`, label `onSurface`, tile transparent on `surface`. |

## Avatar

| Component | Flutter widget | Bindings |
|---|---|---|
| Generated avatar | `CircleAvatar` | bg = `noxAvatarColor(name)` (`nox_brand.dart`), initials `#FFFFFF` `titleMedium`; no valid initials → `forum` glyph `#FFFFFF` on same bg. Circle. |

## Progress

| Component | Bindings |
|---|---|
| `CircularProgressIndicator` (standalone) | `primary` on `surface`. |
| Inside `FilledButton` | `onPrimary`. |
| `LinearProgressIndicator` (5.3 %) | indicator `primary`, track `surfaceVariant`. |

## Chat list item (5.1)

`ListTile`-style row, height ≥ 72, padding 16/12, avatar 40 + gap 16.

| Part | Binding |
|---|---|
| Name | `titleMedium` `onSurface` |
| Preview | `bodyMedium` `onSurfaceVariant` |
| Time | `labelSmall` `onSurfaceVariant` |
| Unread badge | `Badge`: bg `primary`, text `onPrimary` `labelSmall`, shape `full`, cap `99+`; **N=0 → not rendered** |
| Divider | `outlineVariant` (or omit on 8dp rhythm) |

## Message bubble (5.2)

Custom container. Base radius `l` (16); own bottom-right / other bottom-left → 4 — use
`NoxRadius.bubble(isOwn:)`. Padding 12×8, max-width 80%, intra-group gap 2, inter-group 12.

| Part | Own | Other |
|---|---|---|
| Fill | `primaryContainer` | `surfaceContainerHigh` |
| Text | `onPrimaryContainer` | `onSurface` |
| Time | `onPrimaryContainer`@70% | `onSurfaceVariant` |
| Author header | — | `titleMedium` `onSurfaceVariant` |
| Status icon (own) | `schedule` pending / `check` sent → `onSurfaceVariant`; `error_outline` error → `error` | — |

## File chip (attachment)

`surfaceContainerHighest`, shape `xs`. Type icon `onSurfaceVariant` (map in `icons.md`),
name `titleMedium` `onSurface` ellipsis, size `bodyMedium` `onSurfaceVariant`. Remove `×`
(composer only): `close` `onSurfaceVariant`, tap-target 48. Inside own bubble: contrasting tone over `primaryContainer`.

## Composer (5.2)

Container `surfaceContainer`, top divider `outlineVariant`, vertical padding 8, icons 48×48.
Attach `IconButton` `onSurfaceVariant`; Send `IconButton` active `primary` / disabled `onSurface`@38%.

## Identity card (7.1)

`Card` filled `surfaceContainerLow`, shape `m`, elevation 1. ID mask `••••••••` (8) mono `onSurface`;
revealed ID mono wrapped `onSurfaceVariant`. Logout `ListTile` text+icon `error`.

## App bar

`AppBar` container `surface`, title `onSurface` `titleLarge`, icons `onSurface`/`onSurfaceVariant`,
elevation 0 (scrolled-under → level 2). Wordmark `NOX` uses `onSurface`, Bold 700, letter-spacing +0.12em.

## Bottom navigation + docked FAB (4.1)

Custom — not a stock `NavigationBar`. `BottomAppBar` `surfaceContainer` elevation 2 with
`CircularNotchedRectangle` for the FAB cutout. Tabs: selected `primary`, unselected `onSurfaceVariant`,
labels `labelMedium`. FAB `+`: circle, `primaryContainer`/`onPrimaryContainer`, elevation 3,
visible on both tabs (it is an action, not a tab).

## Feedback & overlays

| Component | Flutter | Bindings |
|---|---|---|
| Transient | `SnackBar` | `inverseSurface`/`onInverseSurface`; error variant `errorContainer`/`onErrorContainer`; floats above bottom bar/FAB; auto-dismiss ~4s. |
| Persistent | `MaterialBanner` | `surfaceContainer`, action `primary`, top of screen (e.g. `No connection`). |
| Confirm | `AlertDialog` | `surfaceContainerHigh`, shape `xl`, elevation 5; title `headlineSmall`, body `bodyMedium`, destructive action `error`. |
| Bottom sheet | `showModalBottomSheet` | `surface`, shape `xl` top, elevation 5, drag-handle `onSurfaceVariant`@40%. |
| Fatal error (3.1) | screen | `error_outline` `onSurfaceVariant` 48–96 + `FilledButton`. Blocking (no back) / embeddable (back) variants. |

## Brand-fixed (outside ColorScheme — do NOT theme)

| Surface | Value |
|---|---|
| Splash bg | `brand/canvasDark` `#0C2424` (always dark) |
| QR card (7.1) | `brand/qrSurface` `#FFFFFF` (always light, so it scans in dark) + modules `brand/qrInk` `#0C0C0C` |
| Camera overlay (2.2) | mask `#000000`@55%; reticle stroke `brand/white` 3dp, corners `m`; instruction text `#FAFAFA` `bodyLarge`. Permission-denied overlay = opaque `surface`. |

---

## Mobile → desktop adaptation (same widgets, different shell)

The desktop build **re-arranges the same widgets** — it does not reimplement them. Only the shell differs.

| Mobile | Desktop |
|---|---|
| Bottom `BottomBar` | left `NavigationRail` (80) |
| Full-screen screens | two-pane **list-detail** |
| Bottom sheet | centered **Dialog** |
| File view (pushed) | **lightbox** |
| Chat card / Files (pushed) | right **drawer** |
| Create chat (pushed) | **Dialog** |

Desktop window 1440×900 (M3 *expanded*). Chat list pane 360, settings menu 340, readable thread column ≤ 980.
