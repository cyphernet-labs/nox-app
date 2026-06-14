# План реализации: Инициализация дизайн-системы в `lib/design` (всё, кроме виджетов)

**Ветка**: `002-design-system-init` | **Дата**: 2026-06-14 | **Спека**: [spec.md](spec.md)

**Вход**: Спецификация фичи из `/specs/002-design-system-init/spec.md`

## Резюме

Довести дизайн-слой `nox_app` до полноты: «натянуть» авторитетную дизайн-систему NOX (`docs/design/spec/design-system.md` + машинные токены `docs/design/system/nox-handoff/`) на код — **все non-widget-фундаменты, где бы они ни лежали** (`lib/design` + конфиг шрифтов/иконок/ассетов в `pubspec.yaml` + форматтеры дат/времени и UI-microcopy в `lib/general` + глобальный overlay). Технический подход целиком выводится из блюпринта `docs/blueprints/mobile/06-theming.md` (+ `01`, `10`). По решению владельца охват **максимальный**: полный токенизированный фундамент (ColorScheme light+dark, типошкала, токены формы/высоты/отступов/движения, бренд+аватар) → `AppColors` доведён до полного token-driven набора → **component-сабтемы `ThemeData`** (§9 как theme-конфиг) → сквозные фундаменты (иконки `material_symbols_icons`+`NoxIcons`, нативный sans + бандл `Roboto Mono`, форматтеры, microcopy, аватары, ассеты, overlay) → гигиена (устранение дублей spacing/asset-каналов, фикс дрейфов токенов, выравнивание типо-обёрток, правило регенерации). **Виджеты — вне объёма.** Решение «сабтемы сейчас» переопределяет дефолт блюпринта 06 §3 — блюпринт обновляется в том же change-set (docs-in-sync).

## Технический контекст

**Язык/Версия**: Dart `>=3.12.0 <4.0.0`; Flutter `3.44.1` (пин через FVM, `.fvmrc`).

**Основные зависимости**: `flutter_screenutil` (responsive spacing-токены), `flutter_gen` (канонический канал ассетов), **`material_symbols_icons`** (Material Symbols Rounded — новая зависимость по решению clarify); бандл-шрифт `Roboto Mono` (`assets/fonts/`). Генерируемый Dart `lib/design/theme/nox_*.dart` происходит из DTCG-токенов `nox-handoff/tokens/*.tokens.json` (drop-in + правило «руками не править, регенерировать»; автоматический генератор — вне объёма). `intl` (форматтеры дат). Виджет-библиотеки не добавляются.

**Хранилище**: N/A — дизайн-слой не персистит данные.

**Тестирование**: `flutter_test` (глубокий зеркальный layout `test/`): сборка темы light/dark; **автотесты контраста** (WCAG AA: ≥4.5:1 body, ≥3:1 large/icons) по парам роль/фон `ColorScheme`; детерминизм генерируемого аватара (палитра/хеш/инициалы/`forum`-fallback); карта «тип файла → иконка»; лестницы форматтеров дат; verification отсутствия хардкода. Тесты держат зелёный gate осмысленным.

**Целевая платформа**: iOS, Android, Windows, Linux, macOS. **Web — вне scope.** Типошкала: нативный sans (Roboto/SF по ОС) + бандленный `Roboto Mono` на всех пяти таргетах.

**Тип проекта**: дизайн-слой единого Dart-пакета `nox_app` (+ смежные non-widget-фундаменты в `pubspec.yaml`/`lib/general`). Clean Architecture сохраняется (`design`/`general` — поддерживающие слои; `domain` ни от чего не зависит).

**Цели по производительности**: специфических perf-целей нет; инвариант — сборка темы дешёвая, переключение `themeMode` перерисовывает без потери ролей, стоковая M3-плавность.

**Ограничения**: только токены (никакого хардкода цвета/отступов/типографики/радиусов/длительностей/overlay вне токенного слоя); **источник истины — `nox-handoff/tokens`** (нулевой дрейф; `nox-handoff-2/` не авторитетен); один канонический канал на роль (устранить дубли spacing и ассетов); component-сабтемы из §9; нативный sans + бандл mono; иконки Material Symbols Rounded; a11y — инварианты + тесты контраста; **виджеты не реализуются**; RU-проза / EN-код; line length 140, стоковый `flutter_lints`, `flutter analyze` без ошибок.

**Масштаб/Объём**: все non-widget-фундаменты дизайн-системы (цвет/типографика/форма/высота/отступы/движение/бренд/аватар/иконки/ассеты/форматтеры/microcopy/overlay) + полный `AppColors` + component-сабтемы. Без единого продуктового виджета.

**Открытые неизвестные**: нет `NEEDS CLARIFICATION`. Три развилки закрыты в `/speckit-clarify` (иконки, шрифты, a11y) и записаны в `## Clarifications` спеки. Точная энумерация доп. ролей `AppColors` выводится в `research.md` (Phase 0) из `design-system.md` §9/`overview.md`. Удаление дубликата `nox-handoff-2/` (после переноса FILL-axis `icons.md`) допускается отдельным change-set (FR-020).

## Проверка соответствия конституции

*GATE: проверка против ратифицированной конституции **v1.1.0** (принципы I–V). Перепроверяется после Phase 1.*

| Принцип | Гейт | Статус |
|---|---|---|
| I. Приватность и E2EE | Без PII/крипто; ничего не ослабляет приватность | ✅ PASS — дизайн-слой; нет данных/сети/крипто. A11y/контраст не затрагивают приватность. |
| II. Спека/дизайн-корпус — источник истины | План следует spec + `docs/design/spec/design-system.md` + `nox-handoff`; out-of-scope (виджеты) явный | ✅ PASS — план = проекция дизайн-корпуса; граница «кроме виджетов» зафиксирована; токены = источник истины (проза §2.3 — устаревшая, не источник). |
| III. Блюпринт обязателен | Строим по `docs/blueprints/mobile/06` (+ `01`/`10`) | ✅ PASS — план = проекция блюпринта 06. Решение «component-сабтемы сейчас» переопределяет дефолт 06 §3 — **governed** (решение владельца в clarify), блюпринт 06 правится в этом же change-set (docs-in-sync), не молча. |
| IV. Верность дизайн-системе | M3 light+dark из токенов `nox-handoff`, без хардкода, бренд-фиксы | ✅ PASS — это ядро фичи: полный токенизированный слой, нулевой дрейф, тёмный splash / светлая QR-поверхность сохранены. |
| V. Языковая дисциплина | RU-проза / EN-код/идентификаторы/UI-микрокопия | ✅ PASS — спека/артефакты RU; идентификаторы и `TextConstants` (microcopy) — EN. |

**Гейты пройдены, нарушений нет.** Переопределение дефолта 06 §3 (сабтемы) — управляемое решение владельца, фиксируется правкой блюпринта в том же change-set, а не нарушением. Раздел «Учёт сложности» пуст.

**Post-Design re-check (после Phase 1): ✅ PASS** — сгенерированные артефакты (`research`/`data-model`/`contracts`/`quickstart`) не вводят новых нарушений: `material_symbols_icons` + бандл `Roboto Mono` — это дизайн-фундамент (Принцип IV), виджеты не добавлены, источник истины — токены `nox-handoff`. Уточнение из `research.md`: «дрейф» `outlineVariant` — это **устаревшая проза** `design-system.md` §2.3 (#3F4948), тогда как код и токен уже совпадают (#4E5B58) → чинится проза, не код (FR-017 «в пользу авторитетного токена» — токен и есть код).

## Структура проекта

### Документация (эта фича)

```text
specs/002-design-system-init/
├── plan.md              # этот файл (/speckit-plan)
├── research.md          # Phase 0 — решения (иконки/шрифты/a11y/AppColors-роли/дубли/дрейфы/регенерация)
├── data-model.md        # Phase 1 — «сущности» дизайн-системы (токены/тема/реестры)
├── quickstart.md        # Phase 1 — runnable validation (тема→контраст→шрифты/иконки→gate)
├── contracts/           # Phase 1 — внутренние контракты дизайн-слоя (API для остального приложения)
│   ├── README.md
│   ├── theme-and-tokens.md
│   ├── foundations.md
│   └── accessibility.md
├── checklists/
│   └── requirements.md  # spec-quality (создан /speckit-specify)
└── tasks.md             # Phase 2 — /speckit-tasks (НЕ создаётся этой командой)
```

### Исходный код (корень репозитория)

Затрагиваются дизайн-слой и смежные non-widget-фундаменты единого пакета `nox_app`. **Виджеты (`lib/presentation/**`) не трогаются** (кроме потенциальной сверки, что они не хардкодят стили).

```text
nox_app/
├── pubspec.yaml                         # + material_symbols_icons; fonts: (Roboto Mono); assets/ (шрифты, svg-слоты)
├── assets/
│   ├── fonts/                           # Roboto Mono (бандл для mono-слота)
│   └── svg/ png/ animation/             # слоты ассетов (реальные иллюстрации/лого — внешние поставки, fallback)
├── lib/
│   ├── design/
│   │   ├── theme/
│   │   │   ├── nox_color_scheme.dart    # GENERATED ColorScheme light/dark (из color.{light,dark}.tokens.json); фикс дрейфа
│   │   │   ├── nox_text_theme.dart      # GENERATED TextTheme + wordmark; нативный sans, mono = Roboto Mono
│   │   │   ├── nox_tokens.dart          # GENERATED NoxSpacing/NoxRadius/NoxElevation/NoxDuration/NoxEasing
│   │   │   ├── nox_brand.dart           # GENERATED бренд-фиксы + бренд-палитра + аватар (палитра/хеш/инициалы)
│   │   │   ├── app_colors.dart          # ThemeExtension<AppColors> — ПОЛНЫЙ token-driven набор ролей (было: skeleton)
│   │   │   └── app_theme.dart           # AppTheme.light()/dark() + component-сабтемы (§9)
│   │   ├── app_spacing_tokens.dart      # единый канонический spacing-канал (дубль с NoxSpacing устранён)
│   │   ├── app_text_style_tokens.dart   # выровнен под M3-шкалу noxTextTheme
│   │   ├── app_overlay_style_tokens.dart# overlay-токены (+ глобальное применение)
│   │   ├── nox_icons.dart               # NEW: реестр NoxIcons (Material Symbols Rounded) + карта тип→IconData
│   │   ├── app_images_tokens.dart       # свёрнут в flutter_gen (единый канал ассетов) или ретайрнут
│   │   └── gen/assets.gen.dart          # GENERATED (flutter_gen) — канонический канал ассетов
│   └── general/
│       ├── text_constants.dart          # + сетевые/offline microcopy-строки (EN)
│       └── formatters/date_formatter.dart # + лестницы относительных дат/времени
├── test/design/ (зеркальный)            # контраст (WCAG AA), аватар-детерминизм, тип→иконка, лестницы дат
└── docs/blueprints/mobile/06-theming.md # docs-in-sync: сабтемы-override + источник истины (правится в этом change-set)
```

**Решение по структуре**: дизайн-слой того же single-package `nox_app` (принцип III); никаких новых пакетов/проектов. Охват — широкий (решение владельца): дизайн-система реализуется как все non-widget-фундаменты, включая конфиг в `pubspec.yaml` (шрифты/иконки/ассеты) и поддерживающие фундаменты в `lib/general` (форматтеры/microcopy) — это согласуется с Clean Architecture (`design`/`general` — поддерживающие слои). Виджеты исключены; реальные графические ассеты — внешние поставки (только плумбинг + fallback).

## Учёт сложности

> Нарушений Constitution Check нет — раздел не заполняется.

| Нарушение | Зачем нужно | Почему отвергнут более простой вариант |
|-----------|------------|-------------------------------------|
| — | — | — |
