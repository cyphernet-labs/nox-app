# Implementation Plan: Завести дизайн-систему — ассеты, токены и шрифты

**Branch**: `002-design-system-assets` | **Date**: 2026-06-15 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/002-design-system-assets/spec.md`

## Summary

Завести в `lib/design` + `assets/` абсолютно все подготовленные ресурсы дизайн-системы из `docs/design/system/` — **без** реализации UI Kit, виджетов и экранов. Конкретно: забандлить 37 SVG-иконок (Material Symbols Rounded), бренд-логотип и 3 иллюстрации пустых состояний; забандлить и объявить шрифты `Roboto` (400/500/700) и `Roboto Mono` (400); подтвердить и при необходимости пересинхронизировать девять токен-сетов с авторитетным хендофом `nox-handoff/`; закрыть точечные пробелы токен-классов (полная M3-шкала размеров шрифта в `AppTextStyleTokens`; удаление битого `AppImagesTokens`); обеспечить type-safe доступ через flutter_gen + семантический icon-реестр; привести `pubspec.yaml`, `.gitignore` и затронутые разделы блюпринта в соответствие. Подход к токенам — **сверка + синхронизация** уже доставленного Dart (генерационный пайплайн JSON→Dart вне scope).

## Technical Context

**Language/Version**: Dart `>=3.12.0 <4.0.0`; Flutter `3.44.1` (FVM-pinned, `.fvmrc`).

**Primary Dependencies**: `flutter_svg ^2.3.0` (рендер SVG-иконок/иллюстраций, `currentColor`), `flutter_gen_runner ^5.14.1` + `build_runner` (type-safe аксессоры ассетов → `lib/design/gen/assets.gen.dart`), `flutter_screenutil 5.9.3` (отзывчивые размеры в `AppTextStyleTokens`). Шрифты — нативная декларация `fonts:` в `pubspec.yaml` (без pub-пакета). **Новых рантайм-зависимостей не вводится.**

**Storage**: N/A (нет персистентности, сети и рантайм-состояния).

**Testing**: `flutter_test` (unit/widget) — тесты резолва каждого ассета, наличия объявленных начертаний шрифтов, согласованности токен-сетов с хендофом и полноты тайпскейла; гейт `flutter analyze` без ошибок. `integration_test` — не требуется.

**Target Platform**: iOS, Android, Windows, Linux, macOS (web — вне scope).

**Project Type**: Кросс-платформенное Flutter-приложение, единый пакет `nox_app`; этот срез — **фундамент дизайн-системы** (`lib/design` + `assets/`), без presentation/data/domain-кода.

**Performance Goals**: Рантайм-перф не затрагивается. Цель — отсутствие заметной регрессии холодного старта и разумный прирост размера бандла от забандленных шрифтов (4 `.ttf`) и SVG.

**Constraints**: только design-токены (никакого хардкод-`Color`/`EdgeInsets`/`TextStyle`); codegen-first (один прогон `build_runner`); line length 140; ноль ошибок `flutter analyze`; сгенерированные файлы (`*.gen.dart`) не правятся руками; `lib/design/gen/` — gitignored; ассеты-бинарники **коммитятся** (Flutter уже инициализирован — bootstrap-исключение из CLAUDE.md больше не применяется к ассетам).

**Scale/Scope**: 37 SVG-иконок, 1 логотип (растровый плейсхолдер), 3 иллюстрации-плейсхолдера, 2 семейства шрифтов (4 файла начертаний), 9 токен-сетов, 9 ролей тайпскейла; **0 виджетов / 0 экранов**.

## Constitution Check

*GATE: пройден до Phase 0; перепроверен после Phase 1 (см. ниже).*

| Принцип | Оценка | Обоснование |
|---|---|---|
| **I. Приватность и E2EE** | ✅ PASS | Ни сети, ни PII, ни логов, ни аналитики; только статические ассеты и токены. Поверхность приватности не затрагивается. |
| **II. Спека и дизайн-корпус — источник истины** | ✅ PASS | Фича напрямую служит верности дизайн-корпусу; пройден spec → clarify → plan; источник истины — `docs/design/system/nox-handoff/` (+ `nox-assets/`). Зафиксированный out-of-scope (виджеты/экраны/pending-ордера) не расширяется. |
| **III. Архитектурный блюпринт обязателен** | ✅ PASS | Строим по `docs/blueprints/mobile/` (раскладка `lib/design`, flutter_gen, классы токенов, codegen-first, один пакет). Затронутые разделы блюпринта (`06-theming.md` §0/§1/§5/§7) приводятся в соответствие в том же change-set. Новых пакетов/path-deps нет. |
| **IV. Верность дизайн-системе** | ✅ PASS | Суть фичи — занести токены/ассеты точно из источника; M3 light+dark; brand-fixed-исключения (тёмный splash, светлая QR-поверхность) сохранены; никакого хардкода. |
| **V. Языковая дисциплина** | ✅ PASS | Spec/plan/research — русский; код, имена файлов/идентификаторов, пути, ключи pubspec, коммиты — английский; UI-микрокопи нет (виджеты вне scope). |

**Вывод гейта:** нарушений нет → Complexity Tracking пуст. Платформенно-специфичных нативных подсистем (push/deep-links/secure-storage) фича не касается — desktop-gap из конституции (Принцип III) не активируется.

## Project Structure

### Documentation (this feature)

```text
specs/002-design-system-assets/
├── plan.md              # этот файл
├── research.md          # Phase 0 — решения по шрифтам/иконкам/сверке токенов
├── data-model.md        # Phase 1 — сущности ассетов и токен-сетов
├── quickstart.md        # Phase 1 — гайд по верификации (резолв ассетов, рендер шрифтов, согласованность токенов)
├── contracts/
│   └── design-system-api.md   # Phase 1 — публичная Dart-поверхность дизайн-системы (UI-контракт)
└── checklists/
    └── requirements.md  # из /speckit-specify
```

### Source Code (repository root)

```text
assets/
├── fonts/                         # NEW — забандленные начертания (коммитятся)
│   ├── Roboto-Regular.ttf         #   weight 400
│   ├── Roboto-Medium.ttf          #   weight 500
│   ├── Roboto-Bold.ttf            #   weight 700  (вордмарк NOX)
│   ├── RobotoMono-Regular.ttf     #   weight 400  (ID/ключи)
│   └── README.md                  #   источник + лицензия (Apache-2.0, Google Fonts)
├── png/
│   └── logo.png                   # NEW — бренд-логотип (растровый плейсхолдер, splash)
├── svg/
│   ├── icons/                     # NEW — 37 SVG Material Symbols Rounded (currentColor)
│   │   ├── add.svg … visibility_off.svg
│   └── illustrations/             # NEW — 3 плейсхолдера пустых состояний
│       ├── empty-chats.svg
│       ├── empty-messages.svg
│       └── empty-files.svg
└── animation/                     # без изменений (анимаций в источнике нет — плейсхолдер)

lib/design/
├── gen/
│   └── assets.gen.dart            # GENERATED (flutter_gen) — реальные аксессоры; gitignored
├── nox_icons.dart                 # NEW — семантический icon-реестр из icons.json (обёртка над Assets.svg.icons.*)
├── app_text_style_tokens.dart     # UPDATED — полная M3-шкала размеров шрифта (9 ролей), .sp, color-injecting
├── app_spacing_tokens.dart        # без изменений
├── app_overlay_style_tokens.dart  # без изменений
├── app_images_tokens.dart         # REMOVED — единственный канал путей = flutter_gen
└── theme/
    ├── app_colors.dart            # без изменений (skeleton доп-ролей)
    ├── app_theme.dart             # без изменений (сборка темы)
    ├── nox_color_scheme.dart      # SYNC-verify (уже совпадает с хендофом)
    ├── nox_text_theme.dart        # SYNC-verify (уже совпадает; семейства 'Roboto'/'Roboto Mono')
    ├── nox_tokens.dart            # RE-SYNC (значения совпадают; форматирование к источнику)
    └── nox_brand.dart             # SYNC-verify (brand-fixed + аватары; уже совпадает)

pubspec.yaml                       # UPDATED — fonts: (Roboto/Roboto Mono) + assets: (svg/icons, svg/illustrations, png)
.gitignore                         # без изменений (lib/design/gen/ уже игнорируется; ассеты коммитятся)

test/design/                       # NEW — verification-тесты (резолв ассетов, наличие шрифтов, согласованность токенов)
```

**Structure Decision**: Единый пакет `nox_app` (несущий инвариант блюпринта). Ассеты раскладываются по типу под `assets/` (`svg/icons`, `svg/illustrations`, `png`, `fonts`); flutter_gen генерирует вложенные type-safe аксессоры (`Assets.svg.icons.*`, `Assets.svg.illustrations.*`, `Assets.png.logo`). Семантика и метаданные иконок (FILL, назначение) живут в рукописном `lib/design/nox_icons.dart`, который **ссылается** на flutter_gen-аксессоры, не дублируя строки путей. Токен-Dart остаётся в `lib/design/theme/nox_*.dart` как синхронизированные копии хендофа. Никаких новых слоёв/пакетов.

## Complexity Tracking

> Нарушений Constitution Check нет — раздел не заполняется.
