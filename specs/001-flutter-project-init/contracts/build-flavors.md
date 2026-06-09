# Контракт: сборка и флейворы

> **Источник:** блюпринт `docs/patterns/mobile/09-build-and-secrets-infra.md` (§0, §4, §6, §7, §7a) + `02-dependency-injection.md` §7; требования FR-003, FR-010, FR-012. Compile-time изоляция флейворов, без runtime-ветвления.

## 1. Два compile-time флейвора

Флейворов ровно два: `stage` и `prod`. Флейвор резолвится **на этапе компиляции** из `String.fromEnvironment('app.flavor')` через `AppFlavor.getFlavor()` (`lib/domain/model/app_config/`). Никакого runtime-переключения по флейвору; пустое/неизвестное значение → `prod` (безопасный дефолт). Флейвор-специфичные значения приходят через конфигурацию сборки, читаются `const String.fromEnvironment`. Маппинг флейвор → DI-окружение — в `di-bootstrap.md` (`prod → Environment.prod`, `stage → Environment.dev`).

## 2. Доставка флейвора по платформам

| Платформа | Механизм передачи `app.flavor` |
|---|---|
| Android | Gradle product-flavors (dimension `app`: `stage`/`prod`) + `--dart-define=app.flavor=<flavor>` |
| iOS | per-flavor xcconfig (`Stage.xcconfig`/`Prod.xcconfig`) + schemes (`stage`/`prod`) + `--dart-define=app.flavor=<flavor>` |
| Windows / Linux / macOS | **нет** нативного `--flavor`; флейвор только через `--dart-define-from-file=config/<flavor>.json` |

`config/stage.json` и `config/prod.json` — закоммиченные, **secret-free**, несут только `{"app.flavor": "stage"|"prod"}`. Резолюция `AppFlavor.getFlavor()` на десктопе **идентична** мобильной.

## 3. Идентичность приложения (FR-003)

- Display name: `NOX`. Prod `applicationId`/bundle id: `com.cyphernetlabs.noxapp`; stage: `com.cyphernetlabs.noxapp.stage`.
- **Android/iOS** — обе native-идентичности (prod + stage) через product-flavors / xcconfig.
- **Desktop — prod-only native** (одна нативная конфигурация на платформу):
  - macOS: `PRODUCT_BUNDLE_IDENTIFIER = com.cyphernetlabs.noxapp`, `PRODUCT_NAME = NOX`;
  - Windows: `BINARY_NAME = NOX` + закоммиченный фиксированный GUID (стабильный между сборками), `ProductName = "NOX"`;
  - Linux: `APPLICATION_ID = com.cyphernetlabs.noxapp`, `.desktop` `Name = NOX`.
  - Stage на десктопе виден **только** через `app.flavor` в Dart; distinct stage native-идентичность (и упаковка двух артефактов) — **FUTURE** (`09` §7a/§11a).

## 4. Секреты на десктопе (FR-012)

- Mobile-флейворы потребляют секреты через SOPS+age+mise → `--dart-define-from-file=.secrets-runtime/<flavor>.dart-define.json` (`09` §2–§4).
- **Desktop в скелете secrets-decrypt пропускает** — `--dart-define-from-file=config/<flavor>.json` несёт только `app.flavor`, age-ключ не нужен. Когда у десктопа появятся секреты — расширяется та же схема SOPS+age+mise.
- Реальные ключи конфига (`API_URL`, `API_SIGNATURE_KEY` и т. п.) — **пример/TBD** (бэкенд NOX не выбран, см. `09` §4, `14`).

## 5. Desktop-fallback подсистем (FR-012)

Подсистемы, которые блюпринт определяет только для mobile, на десктопе имеют документированный fallback (проза-only в скелете; DI-wired no-op stub вводится с первым desktop-потребителем — ни одна из них в скелете не резолвится):

| Подсистема | Desktop-станс в скелете |
|---|---|
| Push (FCM) | **disabled/no-op**; `firebase_*` — mobile-only feature-gated deps; `Firebase.initializeApp()` на десктопе не вызывается (пример/TBD, см. `15`) |
| Deep links | **no-op**; нативная схема `nox://` = FUTURE; single-window: warm-link будит то же окно (пример/TBD, см. `13`) |
| Secure storage | задокументированы desktop-бэкенды `flutter_secure_storage` — macOS Keychain / Windows DPAPI / Linux libsecret; identity/wipe-модель (`deleteAll()` + Sembast-wipe на logout) — единый путь; wiring с auth (пример/TBD, см. `14`) |

## 6. CI — 5 таргетов, desktop compile-only

- `ci.yml` — гейт: format-check (140) → один прогон `build_runner` → `analyze` → `test`.
- `compile-check.yml` — пять debug smoke-джобов (`--debug`, **без секретов**): `compile-android` (stage flavor), `compile-ios` (`--no-codesign`), `compile-macos` / `compile-windows` / `compile-linux` (без native `--flavor`; Linux ставит `ninja-build libgtk-3-dev`).
- Launch-verify сейчас: macOS + iOS + Android; Windows/Linux — только compile/build-verify, launch — tracked follow-up (CI-раннеры).
- Packaging/signing десктопа (MSIX / DMG+notarization / AppImage·.deb) — **FUTURE** (`09` §11a).

## Чеклист

- [ ] Два флейвора `stage`/`prod`; `AppFlavor.getFlavor()` из `String.fromEnvironment('app.flavor')`; нет runtime-ветвления; дефолт → `prod`.
- [ ] Android = Gradle flavors, iOS = xcconfig+schemes, desktop = `--dart-define-from-file=config/<flavor>.json` (secret-free, только `app.flavor`).
- [ ] Display name `NOX`; prod `com.cyphernetlabs.noxapp`, stage `.stage`; desktop native — prod-only; distinct stage native = FUTURE.
- [ ] Desktop secrets-decrypt пропущен (нет age-ключа); реальные конфиг-ключи = пример/TBD.
- [ ] Desktop-fallback: push=disabled/no-op, deep-links=no-op (`nox://`=FUTURE), secure-storage=задокументированы бэкенды.
- [ ] CI: `ci.yml`-гейт + `compile-check.yml` (5 debug smoke-джобов, без секретов); packaging/signing = FUTURE.
