# NOX — App icons (all platforms)

Launcher / app icons for **NOX**, generated from the brand mask logo (`assets/logo.png`).
Folder structure mirrors a Flutter project so files drop straight into place. Open
[`index.html`](index.html) for the visual gallery.

> **Installed into the app** in feature `008-app-icons` (drop-in into the native targets;
> see `specs/008-app-icons/`). The reproducible regen path (`flutter_launcher_icons`) is wired in
> `pubspec.yaml` but intentionally **not run** — it would overwrite this hand-crafted set.

> ⚠️ **Source resolution.** The only logo we have is a **200×200 raster** (`assets/logo.png`,
> opaque, backdrop `#151919`). Everything ≤256 px is crisp; **512 px and 1024 px are upscaled**
> and therefore soft. Before store submission, regenerate from a higher-resolution master or the
> **final vector logo** (still pending per `design-system.md §11` / `nox-assets/brand`). All sizes
> here are produced so the pipeline + manifests are ready the moment that vector lands.

---

## Formats by platform — the short answer

| Platform | Format(s) you ship | Key sizes |
|---|---|---|
| **iOS** | PNG set in `AppIcon.appiconset` (**opaque, no alpha**, square — OS rounds corners) | 40·58·60·80·87·120·152·167·180 + **1024** marketing |
| **Android** | **Adaptive icon** = `mipmap-anydpi-v26` XML + foreground PNGs + bg color; legacy square + round PNGs; **512** Play Store | mdpi→xxxhdpi (48–192 legacy / 108–432 fg) + 512 |
| **Windows** | one multi-resolution **`.ico`** | 16·24·32·48·64·128·256 packed in one file |
| **macOS** | **`.icns`** (and `AppIcon.appiconset` for Flutter/Xcode); rounded-rect + margin, with alpha | 16·32·64·128·256·512·1024 (+ @2x) |
| **Linux** | **PNG** in `hicolor` theme dirs + a `.desktop` file | 16·24·32·48·64·128·256·512 |

---

## What's in the box
```
nox-app-icons/
├── index.html                     ← visual gallery (this package, rendered)
├── source/
│   ├── icon-master-1024.png       ← full-bleed opaque master (hero)
│   └── icon-foreground-1024.png   ← Android adaptive foreground (art in safe zone)
├── ios/AppIcon.appiconset/        ← 12 PNGs + Contents.json  → ios/Runner/Assets.xcassets/
├── android/
│   ├── res/mipmap-*/              ← ic_launcher · ic_launcher_round · ic_launcher_foreground
│   ├── res/mipmap-anydpi-v26/     ← ic_launcher.xml · ic_launcher_round.xml (adaptive)
│   ├── res/values/                ← ic_launcher_background.xml (#151919)
│   └── playstore-icon-512.png     ← Play Console listing icon
├── windows/
│   ├── app_icon.ico               ← drop-in → windows/runner/resources/app_icon.ico
│   └── png/                       ← the individual sizes packed into the .ico
├── macos/
│   ├── nox.icns                   ← prebuilt, ready to use
│   ├── nox.iconset/               ← source PNGs (regen with `iconutil -c icns nox.iconset`)
│   └── AppIcon.appiconset/        ← 7 PNGs + Contents.json → macos/Runner/Assets.xcassets/
└── linux/
    ├── hicolor/<size>/apps/nox.png
    └── nox.desktop
```

---

## Install (Flutter targets)

**iOS** — copy `ios/AppIcon.appiconset/` over `ios/Runner/Assets.xcassets/AppIcon.appiconset/`.
iOS icons must be **opaque with no alpha channel**; these are. The system applies the rounded
mask — never round them yourself.

**Android** — copy `android/res/*` into `android/app/src/main/res/`. The adaptive icon (API 26+)
composes `ic_launcher_foreground` over the `ic_launcher_background` color; older devices fall back
to the density `ic_launcher.png` / `ic_launcher_round.png`. Upload `playstore-icon-512.png` in the
Play Console.

**Windows** — replace `windows/runner/resources/app_icon.ico` with `windows/app_icon.ico`.

**macOS** — copy `macos/AppIcon.appiconset/` over `macos/Runner/Assets.xcassets/AppIcon.appiconset/`.
For non-Flutter packaging use `macos/nox.icns` directly.

**Linux** — install each `hicolor/<size>/apps/nox.png` into
`/usr/share/icons/hicolor/<size>/apps/` and `nox.desktop` into `/usr/share/applications/`
(`Icon=nox` resolves by theme).

### Or regenerate everything from one source with `flutter_launcher_icons`
Once a clean high-res/vector master exists, point the package at it:
```yaml
flutter_launcher_icons:
  image_path: "docs/design/system/nox-app-icons/source/icon-master-1024.png"
  android: true
  ios: true
  windows: { generate: true }
  macos: { generate: true }
  adaptive_icon_background: "#151919"
  adaptive_icon_foreground: "docs/design/system/nox-app-icons/source/icon-foreground-1024.png"
```

---

## Notes & deliberate choices
- **Backdrop `#151919`** — the raster logo's own baked background (sampled), not brand
  `canvasDark #0C2424`. Used for the Android adaptive background so the foreground is seamless.
  When the transparent vector logo arrives, switch the bg token to `#0C2424`.
- **macOS shape** — rounded-rect (≈22.4% radius) with ~9% margin, per Apple's icon grid, so it
  looks native in the Dock. iOS/Windows/Linux/Android-legacy are **full-bleed** (each OS masks
  iOS/Android itself).
- **No Android monochrome (themed) layer** — the splatter artwork doesn't reduce to a clean
  single-color glyph by auto-threshold. Add a hand-simplified `<monochrome>` from the vector later;
  until then Android 13+ themed icons fall back to the full-color adaptive icon (valid).
- **App Store alpha** — the iOS `AppIcon.appiconset` PNGs were **flattened to no-alpha** (RGB, composited
  over `#151919`) during `008-app-icons` to satisfy the spec's hard no-alpha requirement (FR-003/SC-004) —
  so they pass App Store Connect's no-alpha check directly, not only via Xcode's build-time strip. (macOS
  keeps its alpha by design — rounded-rect corners.) The `flutter_launcher_icons` config sets
  `remove_alpha_ios: true`, so a future regen stays alpha-free.
