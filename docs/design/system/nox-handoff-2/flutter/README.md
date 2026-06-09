# NOX Flutter theme — drop-in

Generated from `../tokens/`. Same data as the JSON, already in Dart.

## Files
| File | Exports |
|---|---|
| `nox_color_scheme.dart` | `noxLightScheme`, `noxDarkScheme` (`ColorScheme`) |
| `nox_text_theme.dart` | `noxTextTheme` (`TextTheme`), `noxMonoFamily` |
| `nox_tokens.dart` | `NoxSpacing`, `NoxRadius` (+ `bubble(isOwn:)`), `NoxElevation`, `NoxDuration`, `NoxEasing` |
| `nox_brand.dart` | `NoxBrand`, `noxAvatarPalette`, `noxAvatarIndex/Color`, `noxInitials` |
| `nox_theme.dart` | `noxLightTheme`, `noxDarkTheme` (`ThemeData`) |
| `widgets/` | per-widget Dart (`NoxIcon`, `NoxAvatar`, `NoxChatListItem`, `NoxMessageBubble`, `NoxComposer`, `NoxBottomBar`, …) + live `preview.html`. See `widgets/README.md`. |

## Install
1. Copy the five files into `lib/theme/`.
2. Fonts in `pubspec.yaml` (or rely on the platform default sans — Roboto on Android):
   ```yaml
   flutter:
     fonts:
       - family: Roboto
         fonts: [{ asset: fonts/Roboto-Regular.ttf },
                 { asset: fonts/Roboto-Medium.ttf, weight: 500 },
                 { asset: fonts/Roboto-Bold.ttf,   weight: 700 }]
       - family: Roboto Mono
         fonts: [{ asset: fonts/RobotoMono-Regular.ttf }]
   ```
3. Wire it up:
   ```dart
   import 'theme/nox_theme.dart';

   MaterialApp(
     theme: noxLightTheme,
     darkTheme: noxDarkTheme,
     themeMode: ThemeMode.system, // Settings 7.3: System / Light / Dark
   );
   ```

## Notes
- **Use the explicit schemes**, not `ColorScheme.fromSeed`. The roles are hand-tuned; seed
  (`Color(0xFF12B4B4)`) is documented for provenance only.
- **Elevation** = dp via `NoxElevation.*` on `Material`/`Card`. Don't hand-roll `BoxShadow` —
  Flutter renders the M3 tonal overlay + shadow from the dp value (dark = tonal, no shadow).
- **Brand-fixed surfaces** (splash bg, QR card) come from `NoxBrand`, *not* the `ColorScheme` —
  they must not flip with the theme.
- **Avatars**: `noxAvatarColor(name)` + `noxInitials(name)` reproduce the exact deterministic
  logic from `src/tokens.jsx`. `noxInitials` returns `null` → render the `forum` glyph fallback.
- `surfaceVariant` is set (deprecated in M3) only because the `LinearProgressIndicator` track
  references it; new code should prefer `surfaceContainerHighest`.
- `NoxEasing.emphasized` = `Curves.easeInOutCubicEmphasized` (the real M3 two-part curve);
  the cubic-bezier in the token JSON is the simple-cubic fallback for CSS consumers.
