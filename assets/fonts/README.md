# NOX — Bundled fonts

Typography fonts referenced by the generated `noxTextTheme` (`lib/design/theme/nox_text_theme.dart`,
families `Roboto` / `Roboto Mono`). Bundled as static TrueType so the design renders identically on
all five target platforms (iOS, Android, Windows, Linux, macOS) without silent platform fallback.

| File | Family | Weight | License |
|---|---|---|---|
| `Roboto-Regular.ttf` | Roboto | 400 | Apache-2.0 |
| `Roboto-Medium.ttf` | Roboto | 500 | Apache-2.0 |
| `Roboto-Bold.ttf` | Roboto | 700 | Apache-2.0 |
| `RobotoMono-Regular.ttf` | Roboto Mono | 400 | Apache-2.0 |

Declared in `pubspec.yaml` (`flutter > fonts:`). Family strings match `nox_text_theme.dart` exactly
(`_sans = 'Roboto'`, `noxMonoFamily = 'Roboto Mono'`). Weight set covers the M3 type scale (w400/w500)
and the NOX wordmark (Bold 700); no faux-bold synthesis.

## Provenance & license

Both families are licensed under the **Apache License 2.0**.

- **Roboto** (v2.001, © 2011 Google Inc., designer Christian Robertson). Static instances obtained from
  the vendored Apache-2.0 copy at <https://github.com/openmaptiles/fonts/tree/master/roboto>
  (upstream: Google Fonts / <https://github.com/googlefonts/roboto>).
- **Roboto Mono** (© 2015 The Roboto Mono Project Authors). From
  <https://github.com/googlefonts/RobotoMono> (`fonts/ttf/RobotoMono-Regular.ttf`).

Apache-2.0 full text: <https://www.apache.org/licenses/LICENSE-2.0>. These are stock Google fonts with
no NOX modifications; replace from the upstream source if updating.
