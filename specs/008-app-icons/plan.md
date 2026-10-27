# Implementation Plan: App icons — все платформы

**Branch**: `008-app-icons` | **Date**: 2026-06-25 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/008-app-icons/spec.md`

## Summary

Заменить дефолтные иконки Flutter брендовой иконкой NOX на всех пяти таргетах (Android, iOS, macOS, Windows, Linux), используя готовый hand-crafted набор `docs/design/system/nox-app-icons/`. Подход — **hybrid** (Clarifications): drop-in нативных наборов сейчас (лучшая визуальная точность) + закоммиченный, но **не запускаемый** конфиг `flutter_launcher_icons` (на `source/`-мастер, фон `#151919`) как воспроизводимая регенерация под будущий вектор. Фича не трогает `lib/`/Dart — это нативные ассеты + один dev-инструмент + три манифест-правки.

## Technical Context

**Language/Version**: Flutter `3.44.1` (FVM) / Dart `>=3.12.0`. **Dart-кода в `lib/` фича не добавляет** — только нативные платформенные ассеты, манифесты и `pubspec` dev-секция.

**Primary Dependencies**: `flutter_launcher_icons` (**dev_dependency**, конфиг-only — сейчас **не запускается**); нативные системы ассетов: Xcode asset catalogs (iOS/macOS `AppIcon.appiconset`), Android resource system (mipmap + adaptive `anydpi-v26`), Windows `.rc`/`.ico`, Linux `hicolor` + `.desktop`.

**Storage**: N/A.

**Testing**: структурная верификация (наличие файлов в нативных путях + ссылки манифестов; SC-006) + per-platform compile-smoke (`mise run build:<platform>:stage`; SC-002). Dart unit/widget/golden-тесты не применимы (нет `lib/`-кода).

**Target Platform**: iOS, Android, macOS, Windows, Linux. Web — вне scope.

**Project Type**: Flutter кросс-платформенное приложение (нативная asset/branding-конфигурация).

**Performance Goals**: N/A (build-time ассеты, без runtime-влияния).

**Constraints**: не ломать ни одну из 5 compile-smoke сборок (FR-007); iOS — opaque/без alpha (FR-003); Android — adaptive API 26+ с legacy-фолбэком (FR-002); фон adaptive `#151919` — временный (до вектора); размеры 512/1024 — апскейл из 200px (мягкие, принято для пред-релиза).

**Scale/Scope**: 5 платформ; ~60 ассет-файлов; 3 манифест/конфиг-правки (AndroidManifest `roundIcon`, `pubspec` dev-dep + `flutter_launcher_icons` блок); 1 Linux `.desktop`-реконсиляция (`nox` → `nox_app`).

## Constitution Check

*GATE: пройден до Phase 0; повторная сверка после Phase 1 — без изменений.*

- **I. Приватность и E2EE** — N/A: фича не касается данных, сети, идентичности, аналитики. ✅
- **II. Спека/дизайн-корпус = источник истины** — набор лежит в дизайн-корпусе (`docs/design/system/nox-app-icons/`); spec + clarify оформлены. Linux-рассогласование `.desktop` (`nox` vs реальный `nox_app`) — **дрейф, чинится в этом же change-set** (FR-006). Временный фон `#151919` (вместо бренд `#0C2424`) — осознанное задокументированное решение (не молчаливый дрейф). ✅
- **III. Архитектурный блюпринт** — фича не добавляет Flutter/`lib`-кода → несущие инварианты блюпринта (один пакет, Clean Arch, BLoC=Freezed, DI, `RepositoryResult`) не затрагиваются. Иконки — нативный branding-ассет, не одна из gated native-подсистем (build/secrets, push, deep-links, secure storage), поэтому требование «расширить блюпринт на desktop перед работой» не триггерится; наоборот, фича продвигает 5-платформенный паритет, предписанный конституцией. ✅
- **IV. Верность дизайн-системе** — иконка из бренд-марки; временный фон `#151919` и мягкие апскейл-размеры задокументированы как долг до финального вектора; хардкод-цветов в `lib/` нет (это нативная конфигурация, не Dart-UI). ✅
- **V. Языковая дисциплина** — spec/plan/research/quickstart — русский; пути/идентификаторы/команды/`.desktop`-значения/commit — английский. ✅

**Итог: PASS, нарушений нет. Complexity Tracking — пусто.**

## Project Structure

### Documentation (this feature)

```text
specs/008-app-icons/
├── plan.md              # этот файл
├── research.md          # Phase 0 — решения по установке/реконсиляции
├── data-model.md        # Phase 1 — инвентарь ассетов / install-map (вместо runtime-сущностей)
├── quickstart.md        # Phase 1 — гайд верификации (структурная + compile-smoke)
├── contracts/
│   ├── icon-install-map.md        # source → destination → манифест, по платформам
│   └── flutter-launcher-icons.md  # контракт конфига регенерации (hybrid, не запускается)
└── tasks.md             # Phase 2 (/speckit-tasks — НЕ создаётся этим планом)
```

### Source (нативные таргеты, затрагиваемые фичей)

```text
ios/Runner/Assets.xcassets/AppIcon.appiconset/      # заменить целиком (Contents.json + 12 PNG, opaque)
android/app/src/main/
├── AndroidManifest.xml                             # + android:roundIcon="@mipmap/ic_launcher_round"
└── res/
    ├── mipmap-*/ ic_launcher · ic_launcher_round · ic_launcher_foreground   # добавить round+foreground
    ├── mipmap-anydpi-v26/ ic_launcher.xml · ic_launcher_round.xml           # новый adaptive
    └── values/ic_launcher_background.xml                                    # новый bg #151919
macos/Runner/Assets.xcassets/AppIcon.appiconset/    # заменить (имена app_icon_* совпадают с дефолтом)
windows/runner/resources/app_icon.ico               # заменить .ico
linux/packaging/                                     # НОВОЕ: hicolor/* + nox.desktop (packaging-ready)
pubspec.yaml                                         # + dev_dependencies: flutter_launcher_icons + flutter_launcher_icons: блок (не запускается)
docs/design/system/nox-app-icons/                    # источник истины (master в source/ — путь для регена)
```

**Structure Decision**: фича чисто нативная/branding — никаких изменений в `lib/`. Источник ассетов — `docs/design/system/nox-app-icons/` (drop-in готовых наборов). Play Store `playstore-icon-512.png` остаётся в дизайн-корпусе (загружается в Play Console вручную, не в APK). Linux-ассеты кладутся в `linux/packaging/` (репозиторно, packaging-ready) — не потребляются дев-сборкой, видимость в меню — через будущий packaging. Конфиг `flutter_launcher_icons` ссылается на `docs/.../source/` без дублирования мастера в дерево (закрывает Deferred-вопрос из Clarifications).

## Complexity Tracking

> Нарушений Constitution Check нет — раздел не заполняется.
