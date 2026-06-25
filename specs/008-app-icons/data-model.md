# Data Model: App icons — все платформы

Фича **не вводит runtime-сущностей** (нет доменных моделей, БД, состояния). «Модель» здесь — статический инвентарь ассетов и их install-map: какие файлы, откуда, куда и какой манифест их потребляет. Это вход для `/speckit-tasks`.

## Сущность: Icon Master (источник)

| Поле | Значение |
|---|---|
| `master` | `docs/design/system/nox-app-icons/source/icon-master-1024.png` (1024×1024, opaque, full-bleed) |
| `foreground` | `docs/design/system/nox-app-icons/source/icon-foreground-1024.png` (1024×1024, арт в safe-zone, для Android adaptive) |
| `background` | цвет `#151919` (временный; бренд `#0C2424` — после вектора) |
| ограничение | 512/1024 — апскейл из растра 200×200 (мягкие); долг до финального вектора |

## Сущность: Platform Icon Set (5 экземпляров)

Каждый таргет = набор `{ source_dir, destination, consuming_manifest, format }`.

| Платформа | Source (`docs/.../nox-app-icons/`) | Destination (репозиторий) | Потребляющий манифест | Формат / примечание |
|---|---|---|---|---|
| **iOS** | `ios/AppIcon.appiconset/` | `ios/Runner/Assets.xcassets/AppIcon.appiconset/` | `Contents.json` (в наборе) ← `ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon` | 12 PNG + `Contents.json`, opaque/no-alpha; замена папки целиком |
| **Android** | `android/res/*` | `android/app/src/main/res/*` | `AndroidManifest.xml` (`android:icon`, **+`android:roundIcon`**) + `mipmap-anydpi-v26/*.xml` | adaptive (fg над `#151919`) + legacy `ic_launcher`/`_round` по плотностям |
| **macOS** | `macos/AppIcon.appiconset/` | `macos/Runner/Assets.xcassets/AppIcon.appiconset/` | `Contents.json` ← `ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon` | 7 PNG (`app_icon_16..1024`, имена совпадают), rounded-rect+margin, alpha |
| **Windows** | `windows/app_icon.ico` | `windows/runner/resources/app_icon.ico` | `windows/runner/Runner.rc` (`IDI_APP_ICON`) | один мультиразрешённый `.ico` (16–256) |
| **Linux** | `linux/hicolor/*` + `linux/nox.desktop` | `linux/packaging/hicolor/*` + `linux/packaging/nox.desktop` | `.desktop` (`Icon=nox`) → `hicolor` по теме | packaging-ready; не потребляется дев-сборкой |

## Сущность: Regeneration Config (hybrid, не запускается)

| Поле | Значение |
|---|---|
| место | `pubspec.yaml` (`dev_dependencies: flutter_launcher_icons` + блок `flutter_launcher_icons:`) |
| `image_path` | `docs/design/system/nox-app-icons/source/icon-master-1024.png` |
| `adaptive_icon_foreground` | `docs/design/system/nox-app-icons/source/icon-foreground-1024.png` |
| `adaptive_icon_background` | `#151919` |
| таргеты | `android`, `ios`, `macos`, `windows` (`generate: true`); **Linux не поддерживается** пакетом |
| статус | **не запускается** в этой фиче; служит регенерацией под будущий вектор |

## Производные правки (не ассеты)

| Артефакт | Правка | Причина |
|---|---|---|
| `android/app/src/main/AndroidManifest.xml` | + `android:roundIcon="@mipmap/ic_launcher_round"` | потребление round-иконки (R3) |
| `linux/packaging/nox.desktop` | `Exec=nox`→`nox_app`, `StartupWMClass=nox`→`com.cyphernetlabs.noxapp` | реконсиляция с реальным таргетом (R6, Принцип II) |
| `pubspec.yaml` | dev-dep + `flutter_launcher_icons:` блок | воспроизводимость FR-008 (R7) |
| `docs/design/system/nox-app-icons/README.md` | (опц.) пометка «installed into native targets, see specs/008» | трассируемость (FR-009 уже покрыт самим README) |

## Состояния / переходы

Не применимо (статические ассеты). «Жизненный цикл» — однократная установка + будущая регенерация из вектора (вне scope).
