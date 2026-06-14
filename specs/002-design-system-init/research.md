# Исследование / решения: инициализация дизайн-системы в `lib/design` (всё, кроме виджетов)

**Ветка**: `002-design-system-init` | **Фаза**: 0 (исследование) | **Спека**: [spec.md](spec.md) | **План**: [plan.md](plan.md)

## Назначение

Канонический record решений фазы 0 для Feature-002. Все открытые вопросы спеки закрыты в
`## Clarifications` (сессия 2026-06-14: источник иконок, стратегия шрифтов, инфорсмент a11y) плюс
зафиксированные владельцем решения по охвату/глубине/темизации (`## Assumptions`). Этот файл
консолидирует их в формате **Решение / Обоснование / Рассмотренные альтернативы** и выводит
производные решения, которые спека оставляла плану (конкретный набор доп-ролей `AppColors`, набор
component-сабтем, сведение дублей, точные дрейфы токенов). Авторитет по «как» — блюпринт
`docs/blueprints/mobile/` (главный — `06-theming.md`, плюс `01-stack-and-tooling.md`,
`10-code-templates.md`); источник истины дизайна — `docs/design/spec/design-system.md` (v0.2),
`docs/design/spec/overview.md` и машинные токены `docs/design/system/nox-handoff/tokens/*.tokens.json`
(W3C DTCG) → генерируемый Dart `docs/design/system/nox-handoff/flutter/nox_*.dart`.

## Закрытые неизвестные

- **`NEEDS CLARIFICATION` — ноль.** Три clarify-решения (иконки / шрифты / a11y) и четыре
  owner-решения (охват / темизация / глубина / регенерация) разрешают все неизвестные этой фичи.
- **Бэкенд / протокол — не вовлечены.** Фича чисто дизайн-слойная (цвет / типографика / форма /
  иконки / шрифты / форматтеры / microcopy). Сетевых/auth-контрактов не касается, поэтому
  TBD-плейсхолдеры блюпринта `04`/`14`/`15`/`16` для неё не блокер.
- **Источник истины при расхождении.** Прозовый `design-system.md` v0.2 местами разошёлся с
  DTCG-токенами (см. §G). Правило закреплено: **истиной считаются токены `nox-handoff/tokens`**, а не
  устаревшая проза; расхождения сводятся в пользу токена в этом же change-set (docs-in-sync, FR-021).

---

## A. Источник иконок — `material_symbols_icons` + реестр `NoxIcons`

- **Решение**: Иконочный набор — **Material Symbols Rounded** через пакет
  [`material_symbols_icons`](https://pub.dev/packages/material_symbols_icons) (классы `Symbols.*`,
  переменные оси **FILL / weight / grade / optical size**), а не стоковые `Icons.*`. Поверх него —
  реестр имён `NoxIcons` (навигация / действия / статус / типы файлов), сгруппированный по
  семантике, и отдельная карта **«тип файла → `IconData`»** с дефолтом для неизвестного типа. Базовые
  значения берутся из `design-system.md` §8 и `nox-handoff-2/spec/icons.md` (последний — единственный
  источник, явно фиксирующий FILL-ось вместо `*_outlined`-суффикса).
- **Обоснование**: Авторитетный для макетов набор — Material Symbols Rounded (`design-system.md` §8).
  Material Symbols имеет **вариативную ось FILL** (`forum` рендерится outlined при `FILL 0` и filled
  при `FILL 1`) — стоковые `Icons.forum`/`Icons.forum_outlined` запекают fill в имя двумя разными
  константами, тогда как `material_symbols_icons` даёт один глиф с `fill`-параметром, что точно
  совпадает с дизайн-моделью «selected = FILL 1 / unselected = FILL 0» (нав-бар 4.1: `forum`,
  `settings`). Реестр `NoxIcons` + карта типов убирают «магические» `Symbols.*` из кода фич и дают
  единую точку правки маппинга — в духе «только токены» (`06` §9). Дефолт `insert_drive_file` для
  неизвестного типа покрывает edge-case спеки (FR-011, §97 спеки).
- **Рассмотренные альтернативы**:
  - *Стоковые `Icons.*` (Material Icons), без пакета* — отвергнут: нет вариативной FILL-оси (filled и
    outlined — разные именованные константы), хуже ложится на дизайн-модель selected/unselected и на
    `nox-handoff-2/spec/icons.md`; нумерация глифов та же, но управление осями теряется.
  - *Кастомный icon-font / SVG-набор* — отвергнут: дизайн-корпус явно стандартизован на Material
    Symbols Rounded; кастомный набор — лишняя поставка вне объёма (FR-015 ограничивает реальные
    ассеты плумбингом).
  - *Карта «тип файла → иконка» без дефолта* — отвергнута: спека требует детерминированную иконку для
    неизвестного типа (edge-case «что считается неизвестным типом», §97).

**Решённый маппинг (из `design-system.md` §8 + `overview.md` «Файлы» + `nox-handoff-2/spec/icons.md`).**

| Группа `NoxIcons` | Глифы (base ligature, FILL по контексту) |
|---|---|
| Навигация (4.1) | `forum` (Chats), `settings` (Settings), `add` (центральный `+`) |
| Действия | `arrow_back`, `content_paste`, `qr_code_scanner`, `attach_file`, `send`, `flashlight_on`/`flashlight_off`, `cameraswitch`, `search`, `visibility`/`visibility_off`, `content_copy`, `qr_code`, `download`, `edit`, `close` |
| Статусы сообщения | `schedule` (pending), `check` (sent), `error` (FILL 0, error) |
| Empty-state fallback | `forum` (5.1), `chat_bubble` (5.2), `folder_open` (5.4) |
| Прочее | `error` (universal error 3.1), `forum` (avatar-fallback glyph) |

| Тип файла → `IconData` | Глиф |
|---|---|
| image | `image` |
| video | `videocam` |
| audio | `audiotrack` |
| pdf | `picture_as_pdf` |
| document (doc/docx/odt) | `description` |
| spreadsheet (xls/csv) | `table_chart` |
| text | `article` |
| archive (zip/rar/7z) | `folder_zip` |
| **other / unknown (дефолт)** | `insert_drive_file` |

---

## B. Стратегия шрифтов — платформенно-нативный sans + бандленный Roboto Mono

- **Решение**: **Sans** (основной) — платформенно-нативный (Roboto на Android, SF на iOS/macOS,
  системный sans на Windows/Linux), **без хардкода имени `'Roboto'`** в `TextTheme`. **Mono** (слот
  отображения `Your ID`, 7.1) — **бандленный `Roboto Mono`** (файлы под `assets/fonts/` + блок
  `fonts:` в `pubspec.yaml`), чтобы вид ID был детерминирован на всех пяти платформах. Семейство sans
  в `noxTextTheme` задаётся через `null`/платформенный дефолт (не литерал `'Roboto'`); mono — через
  `noxMonoFamily = 'Roboto Mono'`.
- **Обоснование**: Сгенерированный `noxTextTheme` сейчас хардкодит `_sans = 'Roboto'` (`06` §1,
  `nox_text_theme.dart`). На Windows/Linux `Roboto` не установлен → Flutter **молча** падает на
  системный шрифт, ломая типошкалу (метрики/вес расходятся с дизайном) без диагностики — это и есть
  edge-case спеки (§93) и риск SC-005. DTCG-токен `font.family.sans` сам декларирует fallback-стек
  `["Roboto","system-ui","sans-serif"]` — то есть «Roboto если есть, иначе нативный sans», что
  соответствует прозе `design-system.md` §3 («системное: Roboto (Android) / SF Pro (iOS)»). Бандлить
  весь Roboto на desktop ради совпадения с Android было бы лишним весом и не отражает «системный
  sans» из §3; нативный sans корректен. Mono-слот, наоборот, **обязан** быть детерминирован (ID/ключи
  — load-bearing для чтения и сверки), а `Roboto Mono`/`SF Mono`/generic `monospace` дают разный
  рисунок → его бандлим единым файлом для всех пяти таргетов.
- **Рассмотренные альтернативы**:
  - *Оставить хардкод `'Roboto'` для sans* — отвергнут: молчаливый fallback на Windows/Linux (SC-005),
    прямое нарушение §3 и причина clarify-вопроса.
  - *Бандлить и Roboto (sans), и Roboto Mono на всех платформах* — отвергнут: лишний вес ассетов,
    расходится с «системный sans» (§3); унификация sans не требуется дизайном (sans намеренно
    платформенный), требуется только унификация mono.
  - *Mono тоже платформенный (`SF Mono`/`monospace` fallback)* — отвергнут: недетерминированный вид
    ID на Windows/Linux (нет гарантированного mono), а ID — то место, где рисунок шрифта load-bearing.

---

## C. Инфорсмент доступности — документированные инварианты + автотесты контраста

- **Решение**: Правила a11y из `design-system.md` §2.6 фиксируются как **документированные инварианты
  дизайн-слоя** И покрываются **автотестами контраста** пар роль/фон `ColorScheme` (для обеих тем):
  ≥ **4.5:1** для body-текста, ≥ **3:1** для крупного текста / иконок (WCAG AA). Непрозрачность
  таймштампа — **70%** (фиксированный инвариант, см. §D роль `timestamp`). Тесты вычисляют относительную
  яркость пар (`onSurface`/`surface`, `onSurfaceVariant`/`surface`, `onPrimary`/`primary`,
  `onPrimaryContainer`/`primaryContainer`, `onSurface`/`surfaceContainerHigh` и т.д.) и
  верифицируют 8 фонов аватаров против `#FFFFFF` (≥ 4.5:1 по §2.5).
- **Обоснование**: §2.6 — нормативное требование дизайн-системы (Принцип IV конституции). Контраст —
  единственное свойство a11y, объективно проверяемое из токенов без рендера виджетов (которые вне
  объёма), поэтому автотест уместен именно на уровне `ColorScheme`/палитры. Тест ловит регресс при
  будущей регенерации токенов (если дотюнинг ролей в Material Theme Builder, §11 design-system,
  занизит контраст). Правила «не кодировать смысл только цветом» и «таймштамп ≥ AA для своего
  размера» — инварианты-проза (статусы уже несут иконку+текст по §8/§9.2; виджеты их реализуют вне
  этой фичи).
- **Рассмотренные альтернативы**:
  - *Только проза, без автотестов* — отвергнут: не ловит регресс контраста при регенерации; SC-010
    требует именно проходящие автотесты.
  - *Golden-тесты реальных экранов на контраст* — отвергнут: экраны/виджеты вне объёма (FR-023);
    контраст проверяется на парах ролей, а не на отрендеренных пикселях.
  - *Сторонний a11y-линтер/пакет* — отвергнут: достаточно чистой функции относительной яркости
    (WCAG-формула) в тесте; лишняя зависимость не нужна.

---

## D. Набор доп-ролей `AppColors` — выведенный канонический список

- **Решение**: `AppColors` (`ThemeExtension`) доводится со skeleton (`surfaceMuted`, `dividerSubtle`)
  до полного **token-driven** набора семантических доп-ролей — тех, которых **нет** в стоковом M3
  `ColorScheme` и которые требует `design-system.md` §9 / `overview.md`. Каждое поле получает значение
  из токена/роли (не ad-hoc литерал), пролерпливается в `lerp` и задаётся в `Light/DarkAppColors`.
  Решённый набор:

  | Роль `AppColors` | Источник (design-system) | Значение / производное |
  |---|---|---|
  | `timestamp` | §2.6 / §9.2 / §9.3 | `onSurfaceVariant` @ **70%** (метаданные bubble/списка) |
  | `ownTimestamp` | §9.2 | `onPrimaryContainer` @ **70%** (время в своём bubble) |
  | `dividerSubtle` | §9.3 / §9.8 (уже в skeleton) | `outlineVariant` (тонкий разделитель списка/композера) |
  | `surfaceMuted` | §9 (уже в skeleton) | приглушённая поверхность списка (из tonal-surface-ряда) |
  | `disabledContainer` | §9.5 (FilledButton disabled) | `onSurface` @ **12%** (фон disabled) |
  | `disabledContent` | §9.5 / §9.8 (disabled текст/send) | `onSurface` @ **38%** (текст/иконка disabled) |
  | `dragHandle` | §9.10 | `onSurfaceVariant` @ **40%** (drag-handle bottom sheet) |
  | `scannerMask` | §9.9 (brand-fixed) | `#000000` @ **55%** (затемняющая маска QR-сканера) |
  | `scannerReticle` | §9.9 (brand-fixed) | `brand/white` `#FAFAFA` (рамка-прицел, stroke 3dp) |
  | `scannerInstruction` | §9.9 (brand-fixed) | `#FAFAFA` (overlay-инструкция `Aim your camera…`) |

- **Обоснование**: §9 содержит роли, не сводящиеся к стоковому `ColorScheme`: непрозрачные варианты
  (`timestamp` 70%, `dragHandle` 40%, `disabled` 12%/38%) и **brand-fixed** наложения поверх живого
  видео (маска/прицел/инструкция §9.9), которые **намеренно не из темы** (читаемость поверх камеры).
  Их каноническое место — `ThemeExtension<AppColors>` (`06` §2): типобезопасно, mode-dependent,
  читается как `context.appColors.xxx`. `timestamp`/`ownTimestamp` выделены отдельными ролями, потому
  что 70%-альфа — нормативный a11y-инвариант (§2.6, §C), а не произвольная локальная прозрачность.
  Disabled-варианты (12%/38%) — стандартные M3-состояния, но в коде фич их нельзя выражать сырым
  `Color.withOpacity` (правило «только токены», §9 блюпринта), поэтому они становятся именованными
  ролями. Brand-fixed scanner-роли — это и есть FR-009 («бренд-фиксированные component-токены, не
  сводящиеся к ролям `ColorScheme`»); они кладутся в `AppColors` (mode-independent значения, но
  единый канал семантики) либо в `NoxBrand` (см. §H) — каноническое размещение фиксируется планом,
  но **набор ролей решён здесь**.
- **Рассмотренные альтернативы**:
  - *Оставить skeleton из двух полей, цвета брать из `ColorScheme` по месту* — отвергнут: невозможно
    выразить 70%/40%/12%/38%-альфы и brand-fixed scanner-наложения без сырого `withOpacity`/`Color`
    в коде фич (нарушение §9 блюпринта); FR-007 требует полный набор.
  - *Класть непрозрачные варианты как `withValues(alpha:)` прямо в виджетах* — отвергнут: виджеты вне
    объёма, и это «магия» вместо токена; альфа-производные роли должны жить в теме.
  - *Развести scanner-роли как отдельный публичный класс* — рассмотрено; финальное размещение
    (`AppColors` vs `NoxBrand`) — за планом, но это не новая роль-сущность, а вопрос канала.

> **Примечание по `NavigationRail`.** Selected-indicator/labels десктопного рейла берут стоковые
> `secondaryContainer`/`onSecondaryContainer` — **новой роли в `AppColors` не нужно** (`06` §3,
> подтверждено в Feature-001 research). В список доп-ролей не добавляется.

---

## E. Набор component-сабтем `ThemeData` — полная темизация (override дефолта блюпринта 06 §3)

- **Решение**: Тема включает **полный набор component-сабтем `ThemeData`**, сконфигурированных из
  токенов и component-токенов §9, так что стоковые M3-компоненты получают NOX-стиль без локальной
  стилизации. Это **переопределяет** дефолт блюпринта `06` §3 («сабтемы приходят с первой
  фичей-виджетом»); блюпринт `06` обновляется в этом же change-set (docs-in-sync, FR-021/FR-008).
  Решённый маппинг §9 → сабтема:

  | Сабтема `ThemeData` | Источник §9 | Ключевые токены |
  |---|---|---|
  | `cardTheme` (`CardThemeData`) | §9.4, §5 L1 | `shape/m` (12), elevation 1, `surfaceContainerLow` |
  | `filledButtonTheme` | §9.5 | `shape/full`, Label Large, `primary`/`onPrimary`, disabled 12%/38% |
  | `textButtonTheme` | §9.5 | `shape/full`, текст `primary`, Label Large |
  | `outlinedButtonTheme` | §9.5 (контурные) | `shape/full`/`shape/xs`, контур `outline` |
  | `inputDecorationTheme` | §9.5, §9.8 | `shape/xs`, border `outline`/focus `primary`/error `error`, helper/counter `onSurfaceVariant` |
  | `searchBarTheme` | §9.5 | `surfaceContainerHigh`, `shape/full`, elevation 2 |
  | `segmentedButtonTheme` | §9.5 | selected `secondaryContainer`/`onSecondaryContainer`, контур `outline`, `shape/s` |
  | `switchTheme` | §9.5 | track/thumb `primary` (on) / `outline`+`surfaceVariant` (off) |
  | `radioTheme` | §9.5 | selected `primary`, unselected `onSurfaceVariant` |
  | `listTileTheme` | §9.3, §9.4 | прозрачный tile на `surface`, текст `onSurface` |
  | `appBarTheme` | §9.11, §1 wordmark | container `surface`, title `onSurface`, иконки `onSurface`, elevation 0 |
  | `bottomAppBarTheme` | §9.1 | `surfaceContainer`, elevation 2 (notch — на виджете) |
  | `navigationBarTheme` | §9.1 / 4.1 | selected `primary`, unselected `onSurfaceVariant` |
  | `navigationRailTheme` | §9.1 / 4.1 (desktop) | indicator `secondaryContainer`/`onSecondaryContainer` |
  | `floatingActionButtonTheme` | §9.1 | `primaryContainer`/`onPrimaryContainer`, circle (`shape/full`), elevation 3 |
  | `snackBarTheme` | §9.11 | `inverseSurface`/`onInverseSurface` (error — `errorContainer`/`onErrorContainer`) |
  | `bannerTheme` (`MaterialBannerThemeData`) | §9.11 | `surfaceContainer`, action `primary` |
  | `dialogTheme` (`DialogThemeData`) | §9.11 | `surfaceContainerHigh`, `shape/xl`, elevation 5; title Headline Small / body Body Medium |
  | `bottomSheetTheme` | §9.10 | `surface`, `shape/xl` (верх), elevation 5 |
  | `progressIndicatorTheme` | §9.6 | `primary` на `surface`; track `surfaceVariant` |
  | `chipTheme` | §9.7 (file-chip база) | `surfaceContainerHighest`, `shape/xs`, иконка `onSurfaceVariant` |
  | `dividerTheme` | §9.3 / §9.8 | `outlineVariant` |

- **Обоснование**: Owner-решение «темизация — ПОЛНАЯ» (`## Assumptions`, FR-008): когда виджеты
  появятся, им не нужно повторять токены — стиль приходит из темы. Сабтема конфигурируется только
  из **уже решённых** токенов (роли `ColorScheme` + `NoxRadius`/`NoxElevation` из `nox_tokens.dart` +
  типошкала из `noxTextTheme`), поэтому не тянет за собой реализацию виджетов (граница «кроме
  виджетов» соблюдена, FR-023): сабтема — это конфиг темы, не виджет. Каждая строка таблицы
  однозначно отображается из конкретной подсекции §9, что даёт проверяемое покрытие (SC-001).
- **Рассмотренные альтернативы**:
  - *Дефолт блюпринта 06 §3 — только примитивы, сабтемы с первой фичей* — отвергнут owner-решением
    «полная темизация»; зафиксировано как override + обновление блюпринта.
  - *Стилизовать компоненты в самих виджетах при их появлении* — отвергнут: дублировал бы токены в
    каждом виджете, противоречит «всё, кроме виджетов» и правилу «только токены».
  - *Подмножество сабтем (только Card/Button/AppBar)* — отвергнут: спека требует полный набор §9
    как theme-конфиг (SC-001 — 100% разделов-фундаментов).

---

## F. Сведение дублей — один канонический канал на роль

- **Решение**: Для каждой роли остаётся **один** канонический канал; дубль помечается как сводимый и
  сводится в рамках полной доводки (US4):
  - **Spacing — `NoxSpacing` (фиксированные dp) vs `AppSpacingTokens` (отзывчивые `.w/.h`).**
    Канонический канал отступов в коде фич — **`AppSpacingTokens`** (адаптив на `flutter_screenutil`).
    **`NoxSpacing`** остаётся только для контекстов, где скейл нежелателен: `NoxSpacing.minTapTarget`
    (гарантированные 48dp) и `NoxSpacing.screenPadding`. Оба ряда генерируются из одного
    `spacing.tokens.json`, поэтому числа совпадают по построению; роль каждого канала разводится по
    назначению, а не дублируется «на выбор».
  - **Ассеты — `flutter_gen` (`Assets.*`) vs рукописный `AppImagesTokens`.** Канонический канал —
    **`flutter_gen`** (`lib/design/gen/assets.gen.dart`): он подключён в `pubspec.yaml::flutter_gen`,
    прогоняется в CI, type-safe, и единообразен с остальной кодген-генерацией проекта.
    **`AppImagesTokens` сворачивается** в пользу `Assets.*` (рукописный реестр удаляется/перестаёт
    расширяться; миграционная нота: при подключении реального ассета он добавляется в `pubspec`-assets
    и регенерируется `build_runner`, путь читается как `Assets.png/.svg.xxx`).
- **Обоснование**: SC-006 требует один канонический канал на роль. Два правила различны:
  для **spacing** дубль не устраняется удалением класса (оба нужны — адаптив vs фиксированный
  tap-target), а **разводится по назначению** с явным правилом выбора (`06` §4.1); для **ассетов**
  дубль устраняется **в пользу генерируемого** канала (`06` §7), потому что рукописный реестр —
  переходное удобство без преимуществ перед `flutter_gen` после подключения CI.
- **Рассмотренные альтернативы**:
  - *Удалить `NoxSpacing` целиком* — отвергнут: `minTapTarget`/`screenPadding` осмысленно
    фиксированы (48dp tap-target нельзя скейлить ниже гайдлайна); удаление потеряло бы семантику.
  - *Оставить `AppImagesTokens` как канонический* — отвергнут: не type-safe относительно реальных
    файлов, не интегрирован с CI/кодгеном, расходится с проектным паттерном генерации.
  - *Держать оба asset-канала равноправно* — отвергнут: прямое нарушение SC-006 (два параллельных
    канала на одну роль).

---

## G. Дрейфы токенов — `nox-handoff/tokens` как источник истины

- **Решение**: Выявленные расхождения сводятся **в пользу DTCG-токена** `nox-handoff/tokens`
  (FR-017). Реальный дрейф — это рассинхрон **прозы `design-system.md` v0.2 с авторитетными токенами**,
  а не кода с токенами: сгенерированный Dart (`nox-handoff/flutter/`) и текущий `lib/design/theme/
  nox_color_scheme.dart` **совпадают** с токенами; устарела именно прозовая таблица §2.3 (dark).
  Конкретно (DARK):

  | Роль (dark) | Проза `design-system.md` §2.3 | Токен `color.dark.tokens.json` (истина) | Код `lib` |
  |---|---|---|---|
  | `outlineVariant` | `#3F4948` | **`#4E5B58`** | `#4E5B58` ✓ |
  | `surfaceContainerLowest` | `#090F0F` | **`#0C1312`** | `#0C1312` ✓ |
  | `surfaceContainerLow` | `#161D1D` | **`#1C2423`** | `#1C2423` ✓ |
  | `surfaceContainer` | `#1A2120` | **`#222A28`** | `#222A28` ✓ |
  | `surfaceContainerHigh` | `#242B2B` | **`#2C3431`** | `#2C3431` ✓ |
  | `surfaceContainerHighest` | `#2F3635` | **`#37403C`** | `#37403C` ✓ |

  Действие: **код не меняется** (он уже = токен); **проза `design-system.md` §2.3 приводится к токену**
  в том же change-set (docs-in-sync, FR-021). Раздел §2.1 design-system, говорящий «значения §2.2–2.3 —
  выверенный старт, не финальный замер», подтверждает приоритет токена.
- **Обоснование**: FR-017/SC-003 — нулевой дрейф между кодом и `tokens/*.tokens.json`. Сверка показала,
  что код↔токены уже синхронны; единственный носитель дрейфа — устаревшая прозовая таблица. Правило
  спеки прямо предписывает истиной считать токены (Assumptions, edge-case §98). Это исключает риск
  «починить код в неверную сторону» — менять надо прозу.

  > **Замечание о направлении.** Постановка задачи приводила пример как «dark `outlineVariant`
  > #4E5B58 → #3F4948 по токену». По факту авторитетный **токен** = `#4E5B58`, а `#3F4948` — это
  > устаревшее **прозовое** значение §2.3; поэтому корректное сведение «по токену» оставляет код на
  > `#4E5B58` и правит прозу. Зафиксировано здесь во избежание регресса в неверную сторону.

- **Рассмотренные альтернативы**:
  - *Привести код к прозе (`#3F4948` и т.д.)* — отвергнут: нарушил бы FR-017 (код перестал бы
    совпадать с токеном) и противоречит правилу «истина — токены».
  - *Оставить прозу как есть, расхождение игнорировать* — отвергнут: нарушает docs-in-sync (FR-021);
    оставляет два конфликтующих набора значений в дизайн-корпусе.

---

## H. Механизм регенерации — drop-in + правило, без тулинга сейчас

- **Решение**: Практический источник Dart-темы — **уже сгенерированный Dart из
  `nox-handoff/flutter/`** (`nox_color_scheme.dart`, `nox_text_theme.dart`, `nox_tokens.dart`,
  `nox_brand.dart`), копируемый («drop-in») в `lib/design/theme/`. Фиксируется правило: эти файлы —
  **GENERATED, руками не правятся**; при изменении дизайна правится `tokens/*.tokens.json`, затем Dart
  **регенерируется** (или, до автоматического генератора, переносится из обновлённого `nox-handoff/
  flutter/`). Настройка автоматического **DTCG→Dart-тулинга** (Style Dictionary и т.п.) — **вне
  объёма** этой фичи.
- **Обоснование**: Owner-решение (`## Assumptions`, FR-017): принять готовый Dart как практический
  источник + зафиксировать правило регенерации; автоген — отдельная задача, не блокирует доводку
  дизайн-слоя. Правило «руками не править» уже декларировано блюпринтом (`06` §0/§1) и `analysis_
  options.yaml` исключает `lib/design/gen/**` и `docs/**` из анализа; распространяем тот же режим на
  `lib/design/theme/nox_*.dart` (это копии хэндофа). `nox-handoff/flutter/README.md` уже описывает
  drop-in-процедуру и правило «use the explicit schemes, not fromSeed».
- **Рассмотренные альтернативы**:
  - *Поставить Style Dictionary / собственный генератор сейчас* — отвергнут owner-решением как вне
    объёма; преждевременно до стабилизации токенов и не нужно для доводки.
  - *Разрешить ручную правку `nox_*.dart`* — отвергнут: разошёлся бы код с токенами (нарушение
    FR-017/источника истины); правка идёт только через токены.

---

## I. Авторитетность handoff — `nox-handoff/` каноничен, `nox-handoff-2/` после переноса icons.md

- **Решение**: Авторитетный источник дизайн-системы — **`docs/design/system/nox-handoff/`**
  (DTCG-токены + генерируемый Dart). **`nox-handoff-2/`** — дубликат, **не авторитетен**. Уникальное
  non-widget-улучшение из него — **`spec/icons.md` с явной FILL-осью** (нет `*_outlined`-суффикса,
  даёт base-ligature + `FILL 0/1`) — **переносится** в авторитетный корпус (в `nox-handoff/` или
  `design/spec/` рядом с §8) до удаления дубликата. Само **удаление `nox-handoff-2/` отложено** (может
  быть отдельным change-set; FR-020).
- **Обоснование**: Спека прямо называет `nox-handoff/` источником истины, а `nox-handoff-2/` —
  дубликатом (Assumptions). При этом `nox-handoff-2/spec/icons.md` — единственный документ, корректно
  моделирующий FILL-ось (нужную для решения §A — `material_symbols_icons` с `fill`-параметром), тогда
  как `design-system.md` §8 и авторитетный handoff её явно не фиксируют. Перенос сохраняет это знание;
  отложенное удаление избегает риска потерять прочий уникальный контент (`nox-handoff-2/` несёт также
  виджет-исходники `_src/*.jsx`, `spec/components.md|primitives.md|screens.md` — всё это про виджеты,
  вне объёма, поэтому не переносится сейчас).
- **Рассмотренные альтернативы**:
  - *Удалить `nox-handoff-2/` немедленно* — отвергнут: потерял бы FILL-axis icons.md до переноса
    (FR-020 требует перенос уникального контента до удаления).
  - *Считать `nox-handoff-2/` равноправным/авторитетным* — отвергнут: спека фиксирует ровно один
    авторитетный handoff (источник истины — один, US4).
  - *Переносить всё содержимое `nox-handoff-2/` (включая виджеты)* — отвергнут: виджет-артефакты вне
    объёма (FR-023); переносится только non-widget icons.md.

---

## J. Выравнивание типо-обёрток (`AppTextStyleTokens`) под M3-шкалу

- **Решение**: Канонический type scale — сгенерированный `noxTextTheme` (M3-слоты из
  `typography.tokens.json`), доступный через `Theme.of(context).textTheme.*`. Цвето-инъецирующие
  фабрики `AppTextStyleTokens` **выравниваются под эту шкалу** (без рассинхрона размеров/весов):
  текущий skeleton `body 14/w400`, `title 18/w600`, `caption 12/w400` приводится к M3-метрикам
  (`title` → 16/w500 как Title Medium, а не off-scale 18/w600; `caption` → Label Small 11 или Body
  Medium 14 по назначению), либо обёртки тонко переадресуются на слоты `noxTextTheme`. `height` в
  фабриках по-прежнему не задаётся (наследуется из темы, чтобы не скейлить высоту квадратично, `06`
  §3.2/§5).
- **Обоснование**: FR-019/SC — типо-обёртки не должны расходиться с канонической M3-шкалой. Skeleton
  `title 18/w600` не существует в M3-шкале NOX (нет слота 18; ближайший — Title Medium 16/w500 или
  Title Large 22/w400) — это дрейф, который надо устранить. `noxTextTheme` — единственный источник
  размеров/весов/letterSpacing; обёртки лишь добавляют цвет на месте вызова (`06` §5).
- **Рассмотренные альтернативы**:
  - *Оставить off-scale значения обёрток (18/w600 и т.п.)* — отвергнут: рассинхрон с типошкалой
    (FR-019), вводит «магические» размеры мимо токенов.
  - *Удалить `AppTextStyleTokens` целиком, везде только `textTheme.*`* — рассмотрено; финальный
    объём обёрток — за планом, но как минимум они должны быть on-scale (это решено здесь).

---

## K. Прочие non-widget-фундаменты (подтверждение охвата)

Охват owner-решён как «все non-widget-фундаменты, где бы ни лежали» (`## Assumptions`). Эти
фундаменты не требуют отдельного «решения» (значения заданы дизайн-корпусом), но входят в объём и
фиксируются здесь как часть консолидации:

| Фундамент | Источник | Канал реализации |
|---|---|---|
| Форматтеры относительного времени (список 5.1) | `overview.md` «Форматы времени»: `now`/`5 min`/`2 h`/`Yesterday`/`12 May`/`12 May 2025` | `lib/general/formatters/date_formatter.dart` |
| Date-separator ленты (5.2) | `overview.md`: `Today`/`Yesterday`/день недели/`12 May`/`12 May 2025` | `date_formatter.dart` |
| UI-microcopy (сетевые/offline) | `overview.md` «Сетевые ошибки»: `Could not <verb>. Check your connection and try again.` + 5.1-исключение `Could not load chats. Pull to refresh.` | `lib/general/text_constants.dart` (English) |
| Фундамент аватаров | `design-system.md` §2.5 (8-цветная палитра, hash-индекс, инициалы, `forum`-fallback, инициалы `#FFFFFF`) | `nox_brand.dart` (`noxAvatarColor`/`noxInitials`) |
| Overlay system UI | `06` §6/§6.1 (статус-бар по brightness, глобально в `AppRoot`) | `app_overlay_style_tokens.dart` |
| Шрифты/иконки/ассеты — конфиг | `pubspec.yaml` (`fonts:` для Roboto Mono, `flutter.assets`, `material_symbols_icons` в deps) | `pubspec.yaml` |

Аватарная логика верифицируется тестом (детерминизм индекса/цвета/инициалов, `forum`-fallback —
SC-007); форматтеры и microcopy — без новых решений (значения из корпуса).

---

## Итог: статус неизвестных

- **`NEEDS CLARIFICATION` — ноль.** Все решения (A–K) выведены из закрытых clarify-вопросов,
  owner-решений (`## Assumptions`) и авторитетного дизайн-корпуса/блюпринта.
- Фаза 1 (data-model / contracts / quickstart) проецирует эти решения в конкретные артефакты
  дизайн-слоя; фаза реализации сводит дубли (§F), правит прозу-дрейф (§G) и обновляет блюпринт
  `06`/`10` под полную темизацию (§E) — всё в режиме docs-in-sync (FR-021).
