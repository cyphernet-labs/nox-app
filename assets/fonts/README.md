# NOX — Bundled fonts

Typography fonts referenced by the generated `noxTextTheme` (`lib/design/theme/nox_text_theme.dart`,
families `Roboto` / `Roboto Mono`). Bundled as static TrueType so the design renders identically on
all five target platforms (iOS, Android, Windows, Linux, macOS) without silent platform fallback.

| File | Family | Weight | License |
|---|---|---|---|
| `Roboto-Regular.ttf` | Roboto | 400 | Apache-2.0 |
| `Roboto-Medium.ttf` | Roboto | 500 | Apache-2.0 |
| `Roboto-Bold.ttf` | Roboto | 700 | Apache-2.0 |
| `RobotoMono-Regular.ttf` | Roboto Mono | 400 | OFL-1.1 |

Declared in `pubspec.yaml` (`flutter > fonts:`). Family strings match `nox_text_theme.dart` exactly
(`_sans = 'Roboto'`, `noxMonoFamily = 'Roboto Mono'`). Weight set covers the M3 type scale (w400/w500)
and the NOX wordmark (Bold 700); no faux-bold synthesis.

## Provenance & license

The two families come under different licenses, as each file's own `name` table states.

- **Roboto** (v2.001, © 2011 Google Inc., designer Christian Robertson) — **Apache License 2.0**.
  Static instances obtained from the vendored Apache-2.0 copy at
  <https://github.com/openmaptiles/fonts/tree/master/roboto>
  (upstream: Google Fonts / <https://github.com/googlefonts/roboto>).
- **Roboto Mono** (v3.001, © 2015 The Roboto Mono Project Authors) — **SIL Open Font License 1.1**.
  From <https://github.com/googlefonts/RobotoMono> (`fonts/ttf/RobotoMono-Regular.ttf`).

Full texts: Apache-2.0 <https://www.apache.org/licenses/LICENSE-2.0>, OFL-1.1
<https://openfontlicense.org>. These are stock Google fonts with no NOX modifications; replace from the
upstream source if updating.
