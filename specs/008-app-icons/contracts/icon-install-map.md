# Contract: Icon install map (per-platform)

Контракт установки иконок: для каждой платформы — действие, точный destination и проверяемые пост-условия. `SRC = docs/design/system/nox-app-icons`. Это исполняемый контракт для `/speckit-tasks`.

## iOS

- **Действие**: заменить папку `ios/Runner/Assets.xcassets/AppIcon.appiconset/` содержимым `SRC/ios/AppIcon.appiconset/` (включая `Contents.json`).
- **Пост-условия**:
  - В каталоге ровно 12 `Icon-*.png` + `Contents.json` из набора; дефолтных `Icon-App-*.png` не осталось.
  - `Contents.json` ссылается только на присутствующие файлы (`Icon-20-2x`…`Icon-1024`).
  - Все PNG без alpha-канала (opaque).
  - `project.pbxproj`: `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` (без изменений).

## Android

- **Действие**: скопировать дерево `SRC/android/res/*` в `android/app/src/main/res/`; добавить в `AndroidManifest.xml` атрибут `android:roundIcon="@mipmap/ic_launcher_round"` рядом с `android:icon`.
- **Пост-условия**:
  - В каждом `mipmap-{m,h,x,xx,xxx}dpi/` присутствуют `ic_launcher.png`, `ic_launcher_round.png`, `ic_launcher_foreground.png`.
  - `mipmap-anydpi-v26/ic_launcher.xml` + `ic_launcher_round.xml` ссылаются на `@mipmap/ic_launcher_foreground` и `@color/ic_launcher_background`.
  - `values/ic_launcher_background.xml` определяет `ic_launcher_background = #151919`.
  - `AndroidManifest.xml`: `android:icon="@mipmap/ic_launcher"` **и** `android:roundIcon="@mipmap/ic_launcher_round"`; `android:label="NOX"`.
- **Не входит в APK**: `SRC/android/playstore-icon-512.png` (ручная загрузка в Play Console).

## macOS

- **Действие**: заменить папку `macos/Runner/Assets.xcassets/AppIcon.appiconset/` содержимым `SRC/macos/AppIcon.appiconset/`.
- **Пост-условия**:
  - 7 PNG `app_icon_{16,32,64,128,256,512,1024}.png` + `Contents.json` (имена совпадают с дефолтом).
  - `project.pbxproj`: `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` (без изменений).
  - `SRC/macos/nox.icns` / `nox.iconset` в Flutter-таргет **не** копируются.

## Windows

- **Действие**: заменить `windows/runner/resources/app_icon.ico` файлом `SRC/windows/app_icon.ico`.
- **Пост-условия**:
  - `app_icon.ico` — мультиразрешённый (16–256).
  - `windows/runner/Runner.rc`: `IDI_APP_ICON ICON "resources\app_icon.ico"` (без изменений).

## Linux (packaging-ready)

- **Действие**: создать `linux/packaging/`; скопировать `SRC/linux/hicolor/*` → `linux/packaging/hicolor/*` и `SRC/linux/nox.desktop` → `linux/packaging/nox.desktop`; **исправить** `.desktop`.
- **Пост-условия**:
  - `linux/packaging/hicolor/<size>/apps/nox.png` для 16,24,32,48,64,128,256,512.
  - `nox.desktop`: `Name=NOX`, `Icon=nox`, `Comment=Secure messaging`, **`Exec=nox_app`**, **`StartupWMClass=com.cyphernetlabs.noxapp`**, `Categories=Network;InstantMessaging;`.
  - Не потребляется дев-сборкой; видимость в меню — будущий packaging (вне scope).

## Глобальные пост-условия

- Все 5 compile-smoke (`mise run build:<platform>:stage`) — зелёные (FR-007 / SC-002).
- Дефолтная иконка Flutter не отображается ни на одной платформе (SC-001).
- Все ассеты — трекаемые в git (не codegen, не gitignored).
