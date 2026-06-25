# Quickstart: верификация иконок (все платформы)

Гайд проверки фичи `008-app-icons`. Уровень проверки — по Clarifications: для всех 5 структурная проверка + compile-smoke; визуал — на доступном с macOS-дев-машины. Команды из корня репозитория, Flutter через `fvm`/`mise`.

## Prerequisites

- FVM `3.44.1`, `fvm flutter pub get` проходит (после правки `pubspec.yaml` с dev-dep `flutter_launcher_icons`).
- Набор-источник на месте: `docs/design/system/nox-app-icons/`.

## 1. Структурная верификация (SC-006, все 5 платформ, без устройств)

Проверяемо инспекцией файловой системы и манифестов:

- **iOS**: `ios/Runner/Assets.xcassets/AppIcon.appiconset/` содержит набор `Icon-*.png` + `Contents.json` из корпуса; дефолтных `Icon-App-*` нет; PNG opaque (`file`/`sips -g hasAlpha`).
- **Android**: в `android/app/src/main/res/mipmap-*` есть `ic_launcher` + `ic_launcher_round` + `ic_launcher_foreground`; есть `mipmap-anydpi-v26/*.xml` и `values/ic_launcher_background.xml` (`#151919`); в `AndroidManifest.xml` присутствуют `android:icon` **и** `android:roundIcon`.
- **macOS**: `macos/Runner/Assets.xcassets/AppIcon.appiconset/` — 7 `app_icon_*.png` + `Contents.json`.
- **Windows**: `windows/runner/resources/app_icon.ico` — мультиразрешённый (`file app_icon.ico` → «7 icons»).
- **Linux**: `linux/packaging/hicolor/<size>/apps/nox.png` (8 размеров) + `linux/packaging/nox.desktop` с `Exec=nox_app` и `StartupWMClass=com.cyphernetlabs.noxapp`.

## 2. Compile-smoke (SC-002, все 5 платформ)

Сборка не должна ломаться после замены ассетов:

```bash
mise run build:android:stage
mise run build:ios:stage
mise run build:macos:stage
mise run build:windows:stage   # на Windows-хосте/CI
mise run build:linux:stage     # на Linux-хосте/CI
```

Ожидание: каждая собирается (`--debug`) без ошибок. Windows/Linux — на соответствующих хостах/CI (`compile-check.yml`).

## 3. Визуальная проверка (где дотягивается дев-машина)

- **macOS**: `fvm flutter run -d macos --dart-define-from-file=config/stage.json` → иконка NOX в Dock и переключателе приложений.
- **iOS (sim)**: `fvm flutter run -d <ios-sim>` → иконка NOX на домашнем экране симулятора.
- **Android (emulator)**: `fvm flutter run -d <android-emu>` → иконка NOX в лаунчере (adaptive под маской устройства).
- **Windows / Linux**: визуал отложен до доступности ОС/CI (структурная проверка + compile-smoke выше — достаточны для DoD этой фичи).

## 4. Sanity конфига регенерации (не запускать генератор)

- `fvm flutter pub get` резолвит `flutter_launcher_icons` (dev) без конфликтов.
- Блок `flutter_launcher_icons:` присутствует и указывает на `docs/.../source/*`, `adaptive_icon_background: "#151919"`.
- **Не запускаем** `flutter_launcher_icons` в этой фиче (перезатёр бы crafted-набор — см. `contracts/flutter-launcher-icons.md`).

## Definition of Done (свод)

- [X] §1 структурная проверка — зелёная на всех 5.
- [X] §2 compile-smoke — зелёный на всех 5 (`compile-check.yml` dispatched, 5/5 success).
- [ ] §3 визуал — резидуал (требует устройства/дисплея; структурная + 5/5 build — высокая уверенность).
- [X] §4 `pub get` ок, генератор не запускался.
- [X] Дефолтная иконка Flutter не отображается нигде (SC-001) — подтверждено структурно.
