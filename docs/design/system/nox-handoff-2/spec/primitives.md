# NOX — Primitives & widgets spec (→ Flutter)

Every primitive/widget in the design system, in a form that maps 1:1 to Flutter. For each:
a brief description, the Dart symbol that implements it, its props/API, and the token bindings.
Live visual reference: `../flutter/widgets/preview.html` (renders each widget next to its Dart).
Dart source: `../flutter/widgets/*.dart`. Ground truth: `src/m3.jsx`, `src/chats-parts.jsx`.

Two kinds of widget:
- **Stock-themed** — a plain Material 3 widget styled entirely by `nox_theme.dart`. No custom class;
  just use the Flutter widget. Listed here for the binding + correct usage.
- **Custom** — a `Nox*` widget in `../flutter/widgets/`. Reproduces a NOX-specific composition.

Colors are `Theme.of(context).colorScheme` roles; text is `Theme.of(context).textTheme`;
spacing/radius/elevation are `NoxSpacing` / `NoxRadius` / `NoxElevation` (`nox_tokens.dart`).

---

## Primitives (`nox_primitives.dart`)

### NoxIcon — Material Symbols glyph · *custom*
Thin wrapper over `Icon` pinning the Rounded axes (weight 400, optical 24, grade 0) and exposing
`fill` (0 outlined / 1 filled). All NOX icons are Material Symbols Rounded.
- **API:** `NoxIcon(IconData icon, {double size = 24, Color? color, double fill = 0})`
- **Bindings:** default color `onSurfaceVariant`. Icon names → `icons.json` (nox-assets).

### NoxSpinner — indeterminate progress · *stock wrapper*
`CircularProgressIndicator` sized + colored. Standalone → `primary`; inside a `FilledButton` → `onPrimary`.
- **API:** `NoxSpinner({double size = 24, Color? color, double strokeWidth = 3})`

### NoxAvatar — generated chat avatar · *custom*
Deterministic background from the name hash; white initials, or a white `forum` glyph when there
are no valid initials. Always a circle.
- **API:** `NoxAvatar({required String name, double size = 40})`
- **Bindings:** bg `noxAvatarColor(name)` (`nox_brand.dart`); initials `#FFFFFF` `titleMedium`-ish (size·0.4, w500).

### NoxFileGlyph — file-type icon tile · *custom*
Type icon in a soft tinted rounded square (file lists 5.4, file view 5.3).
- **API:** `NoxFileGlyph({required NoxFileType type, double iconSize = 24, double box = 44})`
- **Bindings:** fill = `noxFileColor(type)`@14%, radius `box·0.27`, icon = `noxFileColor(type)`.

### File maps · *helpers*
`noxFileIcon(NoxFileType)` → `Symbols.*`; `noxFileColor(NoxFileType)` → brand color.
`NoxFileType { image, video, audio, pdf, doc, sheet, text, archive, other }`. (audio→music_note,
other→draft, to match the shipped SVG set.)

---

## Buttons & input (stock-themed — see `nox_theme.dart`)

### Primary button — `FilledButton` · *stock*
- **Use:** `FilledButton(onPressed: …, child: Text('Sign in'))`. Loading → put a `NoxSpinner(size:18,
  color: cs.onPrimary)` as the child. With icon → `FilledButton.icon`.
- **Bindings:** bg `primary` / fg `onPrimary`, `StadiumBorder`, `labelLarge`, min-height 48.
  Disabled: bg `onSurface`@12%, text `onSurface`@38% (M3 default).

### Secondary button — `TextButton` · *stock*
- **Bindings:** text `primary`, `StadiumBorder`, `labelLarge`. Destructive variant → `foregroundColor: cs.error`.

### Icon action — `IconButton` · *stock*
- **Use:** `IconButton(onPressed: …, icon: NoxIcon(Symbols.search))`. 48×48 tap target.
- **Bindings:** icon `onSurfaceVariant`, or `primary` when active.

### Text field — `TextField` (outlined) · *stock*
- **Use:** `TextField(decoration: InputDecoration(labelText: …, helperText: …, counterText: …))`.
  Mono ID field (7.1): `style: TextStyle(fontFamily: noxMonoFamily)`. Availability check → put a
  `NoxSpinner(size:18)` in `InputDecoration.suffixIcon`.
- **Bindings:** shape `xs`, border `outline` → focus `primary` (2dp) → error `error`; helper/counter
  `onSurfaceVariant`. All set in `inputDecorationTheme`.

---

## Search

### NoxSearchBar — persistent search (5.1) · *custom*
Brand-teal search icon (NOX accent, not a theme role), `surfaceContainerHigh`, stadium, elevation 2.
Tapping opens the full search view.
- **API:** `NoxSearchBar({String? value, String hint = 'Search', VoidCallback? onTap})`

> Expanded search **view** (app-bar search) = a normal `Scaffold` with a search `AppBar` (back +
> `TextField`) over a results `ListView` of `NoxChatListItem`. No custom widget needed.

---

## Chat & messaging (`nox_widgets.dart`)

### NoxChatListItem — chat row (5.1) · *custom*
Avatar (with subtle ring) + name + preview + time + unread badge. Unread emphasis: name w600,
preview `onSurface`, time `primary`, badge shown. Badge hidden at 0, caps `99+`. Min height 72.
- **API:** `NoxChatListItem({required String name, required String preview, required String time,
  int unread = 0, VoidCallback? onTap})`

### NoxFileChip — attachment chip (§9.7) · *custom*
Type icon + name (ellipsis) + size. Standalone → `surfaceContainerHighest`. Inside a bubble
(`inBubble: true, onColor: <bubble text>`) → tint derived from the bubble text color. Optional remove ×.
- **API:** `NoxFileChip({required NoxFileType type, required String name, required String size,
  bool inBubble = false, Color? onColor, bool removable = false, VoidCallback? onRemove})`

### NoxMessageBubble — message bubble (5.2) · *custom*
Base radius `l`; own bottom-right / other bottom-left clip to `xs` (`NoxRadius.bubble(isOwn:)`).
Own = `primaryContainer`; other = `surfaceContainerHigh`. Optional file chip inside. Own status:
pending `schedule` / sent `check` / error `error` (error tinted `error`). Max width 80%.
- **API:** `NoxMessageBubble({required bool isOwn, String? text, required String time,
  NoxMsgStatus status = NoxMsgStatus.none, Widget? file, bool isLast = false})`
- **Enum:** `NoxMsgStatus { none, pending, sent, error }`

### NoxComposer — message input (5.2 §9.8) · *custom*
`surfaceContainer`, top divider, optional attachment chip above the row. Attach + text + send;
send active → `primary` filled, else `onSurface`@38%.
- **API:** `NoxComposer({String? value, Widget? attachment, bool sendActive = false,
  VoidCallback? onAttach, VoidCallback? onSend})`

### NoxEmptyState — empty list state · *custom*
Illustration placeholder (thin outline + brand accents) + headline + message. Swap the placeholder
box for a real SVG (`nox-assets/illustrations`) when art ships.
- **API:** `NoxEmptyState({required IconData glyph, required String title, required String message})`

### NoxSegmented — single-select segmented · *stock wrapper*
Thin generic over `SegmentedButton`; theme provides selected `secondaryContainer` + shape.
- **API:** `NoxSegmented<T>({required Map<T,String> options, required T selected, required ValueChanged<T> onChanged})`

---

## Shell & feedback (`nox_scaffold.dart`)

### NoxSplashHairline — brand-splash rule · *custom*
3dp horizontal gradient (teal→lime→gold→coral→red) under the app bar — the C-direction signature.
Implements `PreferredSizeWidget` → drop into `AppBar.bottom`. Mobile: under each app bar; desktop: once.

### NoxWordmark — "NOX" title · *custom*
Roboto Bold 700, letter-spacing +0.12em. Use as the chats `AppBar` title.

### NoxBottomBar + NoxCreateFab — bottom nav + docked FAB (4.1) · *custom*
`BottomAppBar` (`surfaceContainer`, elev 2) with `CircularNotchedRectangle`; two tabs
(Chats/Settings, selected `primary` + filled icon). The `+` FAB (`primaryContainer`, elev 3, circle)
docks into the notch and is visible on both tabs — it's an action, not a tab.
- **Use:** `Scaffold(bottomNavigationBar: NoxBottomBar(active:…, onSelect:…),
  floatingActionButton: NoxCreateFab(onPressed:…),
  floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked)`
- **Enum:** `NoxTab { chats, settings }`

### showNoxSnackBar — transient feedback (§9.11) · *helper*
Neutral = `inverseSurface`/`onInverseSurface`, action `inversePrimary`; error =
`errorContainer`/`onErrorContainer`. Floats, shape `xs`.
- **API:** `showNoxSnackBar(context, {required String text, String? actionLabel, VoidCallback? onAction, bool error = false})`

### showNoxBanner — persistent banner (offline) · *helper*
`MaterialBanner`, `surfaceContainer`, leading icon `onSurfaceVariant`, action `primary`. Top of screen.
- **API:** `showNoxBanner(context, {required String text, IconData icon = Symbols.wifi_off, String? actionLabel, VoidCallback? onAction})`

---

## Overlays (stock-themed)

| Widget | Flutter | Bindings |
|---|---|---|
| Confirm dialog (Logout) | `AlertDialog` | `surfaceContainerHigh`, shape `xl`, elev 5; title `headlineSmall`, body `bodyMedium`, destructive action `error`. Set in `dialogTheme`. |
| Bottom sheet (QR 7.1) | `showModalBottomSheet` | `surface`, shape `xl` top, elev 5. **QR card inside is brand-fixed white** (`NoxBrand.qrSurface`). Set in `bottomSheetTheme`. |
| Card (identity 7.1) | `Card` | `surfaceContainerLow`, shape `m`, elev 1. Set in `cardTheme`. |

---

## Adaptation (desktop reuses these same widgets)

Desktop does not reimplement widgets — it re-arranges them in a different shell. Bottom bar →
`NavigationRail`; full screens → two-pane list-detail; bottom sheet → centered `Dialog`; pushed
screens → lightbox / right drawer. The leaf widgets (`NoxChatListItem`, `NoxMessageBubble`,
`NoxFileChip`, `NoxComposer`, …) are identical on both. See `components.md` for the mapping.
