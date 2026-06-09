# Контракт: сборка и флейворы

> **Источник:** блюпринт `docs/patterns/mobile/09-build-and-secrets-infra.md` (§0, §4, §6, §7, §7a) + `02-dependency-injection.md` §7; требования FR-003, FR-010, FR-012. Compile-time изоляция флейворов, без runtime-ветвления.

## 1. Два compile-time флейвора

Флейворов ровно два: `stage` и `prod`. Флейвор резолвится **на этапе компиляции** из `String.fromEnvironment('app.flavor')` через `AppFlavor.getFlavor()` (`lib/domain/model/app_config/`). Никакого runtime-переключения по флейвору; пустое/неизвестное значение → `prod` (безопасный дефолт). Флейвор-специфичные значения приходят через конфигурацию сборки, читаются `const String.fromEnvironment`. Маппинг флейвор → DI-окружение — в `di-bootstrap.md` (`prod → Environment.prod`, `stage → Environment.dev`).

## 2. Доставка флейвора по платформам

| Платформа | Механизм передачи `app.flavor` (скелет) |
|---|---|
| Android | `--dart-define-from-file=config/<flavor>.json` (нативные Gradle product-flavors — **отложены**, carve-out) |
| iOS | `--dart-define-from-file=config/<flavor>.json` (нативные xcconfig/schemes — **отложены**, carve-out) |
| Windows / Linux / macOS | `--dart-define-from-file=config/<flavor>.json`; нативного `--flavor` нет |

`config/stage.json` и `config/prod.json` — закоммиченные, **secret-free**, несут только `{"app.flavor": "stage"|"prod"}`. Резолюция `AppFlavor.getFlavor()` **идентична** на всех платформах.

**Skeleton carve-out:** нативные mobile-флейворы (Android Gradle product-flavors, iOS xcconfig+schemes) и distinct stage native-идентичность отложены до первой реальной per-flavor нативной потребности — у скелета per-flavor нативной разницы нет, flavor живёт только в Dart через `app.flavor`, единообразно на пяти платформах (блюпринт 09 §6/§7, как desktop §7a).

## 3. Идентичность приложения (FR-003)

- Display name: `NOX`. Prod `applicationId`/bundle id: `com.cyphernetlabs.noxapp`; stage: `com.cyphernetlabs.noxapp.stage`.
- **Android/iOS (скелет)** — prod-only native, как desktop; обе native-идентичности (prod + stage) через product-flavors / xcconfig — **FUTURE** (вместе с нативными mobile-флейворами).
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
- `compile-check.yml` — пять debug smoke-джобов (`--debug`, **без секретов**): `compile-android` (stage через `--dart-define-from-file`), `compile-ios` (`--no-codesign`), `compile-macos` / `compile-windows` / `compile-linux`; нативного `--flavor` нет нигде (Linux ставит `ninja-build libgtk-3-dev`).
- Launch-verify сейчас: macOS + iOS + Android; Windows/Linux — только compile/build-verify, launch — tracked follow-up (CI-раннеры).
- Packaging/signing десктопа (MSIX / DMG+notarization / AppImage·.deb) — **FUTURE** (`09` §11a).

## Чеклист

- [ ] Два флейвора `stage`/`prod`; `AppFlavor.getFlavor()` из `String.fromEnvironment('app.flavor')`; нет runtime-ветвления; дефолт → `prod`.
- [ ] Скелет: все платформы = `--dart-define-from-file=config/<flavor>.json` (secret-free, только `app.flavor`); нативные mobile-флейворы (Gradle / xcconfig) = FUTURE.
- [ ] Display name `NOX`; prod `com.cyphernetlabs.noxapp`; native — prod-only на всех платформах (скелет); distinct stage native (`.stage`) = FUTURE.
- [ ] Desktop secrets-decrypt пропущен (нет age-ключа); реальные конфиг-ключи = пример/TBD.
- [ ] Desktop-fallback: push=disabled/no-op, deep-links=no-op (`nox://`=FUTURE), secure-storage=задокументированы бэкенды.
- [ ] CI: `ci.yml`-гейт + `compile-check.yml` (5 debug smoke-джобов, без секретов); packaging/signing = FUTURE.
