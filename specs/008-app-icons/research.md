# Research: App icons — все платформы

Phase 0. Источник набора и его README уже сняли большинство неизвестных; здесь фиксируются решения по установке и реконсиляции. Формат: Decision / Rationale / Alternatives.

## R1. Метод установки (hybrid)

- **Decision**: drop-in готовых per-platform наборов из `docs/design/system/nox-app-icons/` **сейчас**; параллельно закоммитить конфиг `flutter_launcher_icons` (dev) на `source/`-мастер, но **не запускать** его.
- **Rationale**: набор отревьюен (`index.html`) и содержит ручную пер-платформенную трактовку (macOS rounded-rect + маржин, Android adaptive foreground в safe-zone, opaque iOS), которую генератор из одного PNG воспроизвёл бы иначе/хуже. Конфиг закрывает FR-008 (воспроизводимость) и готовит регенерацию под будущий вектор. (Clarifications 2026-06-25.)
- **Alternatives**: только drop-in (нет воспроизводимого пути в проекте); только генератор сейчас (перезатёр бы crafted-набор) — отклонены.

## R2. iOS

- **Decision**: заменить `ios/Runner/Assets.xcassets/AppIcon.appiconset/` целиком (`Contents.json` + 12 PNG) присланным набором.
- **Rationale**: `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` (подтверждено в `project.pbxproj`). Присланный `Contents.json` ссылается на свои имена (`Icon-20-2x.png`…`Icon-1024.png`), отличные от дефолтных `Icon-App-*` — поэтому заменяем **папку целиком** (не отдельные PNG), чтобы манифест и файлы были согласованы. PNG непрозрачные (без alpha) — требование iOS соблюдено.
- **Alternatives**: подменить только PNG, оставив дефолтный `Contents.json` — отклонено (имена не совпадут).

## R3. Android (adaptive + legacy + manifest)

- **Decision**: скопировать `android/res/*` в `android/app/src/main/res/` (mipmap-* `ic_launcher`/`ic_launcher_round`/`ic_launcher_foreground`, `mipmap-anydpi-v26/*.xml`, `values/ic_launcher_background.xml`) **и** добавить в `AndroidManifest.xml` атрибут `android:roundIcon="@mipmap/ic_launcher_round"`.
- **Rationale**: текущий `res/` содержит только `ic_launcher.png` (без round/foreground/adaptive); манифест объявляет `android:icon`, но не `android:roundIcon`. Adaptive (API 26+) активируется автоматически наличием `anydpi-v26` (foreground над `@color/ic_launcher_background`); legacy-устройства берут density `ic_launcher.png`; `roundIcon` нужен явным атрибутом, чтобы лаунчеры с круглой маской взяли `ic_launcher_round`. `android:label="NOX"` уже стоит.
- **Alternatives**: не добавлять `roundIcon` — отклонено (FR-002 требует round-фолбэк). Monochrome (themed) слой — **не добавляем** (артворк не редуцируется в чистый глиф; Android 13+ падает в полноцветный adaptive — валидно), отложено до вектора.
- **Note**: `playstore-icon-512.png` в APK не входит — остаётся в дизайн-корпусе для ручной загрузки в Play Console.

## R4. macOS

- **Decision**: заменить `macos/Runner/Assets.xcassets/AppIcon.appiconset/` присланным набором.
- **Rationale**: имена присланных PNG (`app_icon_16`…`app_icon_1024`) **точно совпадают** с дефолтными у Flutter macOS, `AppIcon` — имя по умолчанию (подтверждено). Чистый drop-in; rounded-rect+маржин уже вшиты в ассеты (нативный вид Dock). `nox.icns`/`nox.iconset` — для не-Flutter упаковки, в Flutter-таргете не нужны.
- **Alternatives**: — .

## R5. Windows

- **Decision**: заменить `windows/runner/resources/app_icon.ico` присланным `app_icon.ico`.
- **Rationale**: `windows/runner/Runner.rc` ссылается `IDI_APP_ICON ICON "resources\app_icon.ico"` (подтверждено). Присланный `.ico` мультиразрешённый (16–256). Drop-in без правки `.rc`.
- **Alternatives**: — .

## R6. Linux (packaging-ready + реконсиляция .desktop)

- **Decision**: положить `hicolor/<size>/apps/nox.png` (16–512) и `nox.desktop` в `linux/packaging/` (репозиторно); **исправить** `.desktop`: `Exec=nox_app`, `StartupWMClass=com.cyphernetlabs.noxapp` (`Icon=nox`, `Name=NOX`, `Comment=Secure messaging` — без изменений).
- **Rationale**: Flutter-Linux-сборка не потребляет `hicolor`/`.desktop` автоматически — видимость в меню требует системной установки/пакетирования (вне scope, Clarifications). Присланный `.desktop` использует `Exec=nox`/`StartupWMClass=nox`, но реальный `BINARY_NAME=nox_app` и `APPLICATION_ID=com.cyphernetlabs.noxapp` (подтверждено в `linux/CMakeLists.txt` / `my_application.cc`) — иначе ярлык не запустит бинарь и не свяжет окно с иконкой. Реконсиляция — дрейф-фикс по Принципу II.
- **Alternatives**: переименовать `BINARY_NAME` в `nox` (ripple в app-id/упаковку) — отклонено; CMake `install()`-wiring / полный packaging — отклонены как несоразмерные (Clarifications).

## R7. Конфиг `flutter_launcher_icons` (hybrid, не запускается)

- **Decision**: добавить в `pubspec.yaml` `dev_dependencies: flutter_launcher_icons` + блок `flutter_launcher_icons:` с `image_path`/`adaptive_icon_foreground` на `docs/design/system/nox-app-icons/source/*` и `adaptive_icon_background: "#151919"`; **не запускать** генератор в рамках этой фичи.
- **Rationale**: воспроизводимый путь под будущий вектор (FR-008) без перезаписи crafted-набора сейчас. Источник остаётся в `docs/.../source/` — **без дублирования** мастера в дерево проекта (закрывает Deferred-вопрос Clarifications).
- **Caveat (задокументировать)**: запуск генератора в будущем (а) **перезапишет** все iOS/Android/macOS/Windows ассеты выводом генератора (другая трактовка macOS/adaptive — принимается вместе с вектором) и (б) **не покрывает Linux** (пакет его не поддерживает) — ручной Linux-шаг остаётся в любом случае.

## R8. Очистка дефолтов и git-tracking

- **Decision**: замена «папкой целиком» (iOS/macOS appiconset, Windows `.ico`) и перезапись `ic_launcher.png` убирают дефолтные иконки Flutter; все иконки — **трекаемые** ассеты в git (не codegen, не игнорируются).
- **Rationale**: дефолт исчезает автоматически при wholesale-замене; нет «осиротевших» дефолт-файлов, кроме Android, где старый `ic_launcher.png` перезаписывается, а round/foreground/adaptive — добавляются.
- **Verification depth (Clarifications)**: для всех 5 — compile-smoke + структурная проверка (файлы+манифесты, SC-006); визуал на macOS/iOS-sim/Android-emulator; Windows/Linux-визуал отложен.
