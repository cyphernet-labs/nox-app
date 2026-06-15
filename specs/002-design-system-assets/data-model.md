# Data Model: Завести дизайн-систему — ассеты, токены и шрифты

**Feature**: `002-design-system-assets` | **Date**: 2026-06-15 | **Phase**: 1

Рантайм-модели данных (entity/DB) у фичи нет — она заводит **статический каталог** ассетов и токенов. Ниже — сущности этого каталога: атрибуты, правила валидации/согласованности и связи. «Validation» здесь = инвариант, проверяемый верификацией (quickstart/тесты), а не рантайм-валидатор.

---

## 1. Asset entities

### 1.1 Icon (Material Symbols Rounded)

Источник списка: `docs/design/system/nox-assets/icons/icons.json`. Файлы: `…/icons/svg/` → `assets/svg/icons/`.

| Поле | Тип | Описание |
|---|---|---|
| `name` | string | Базовая лигатура Material Symbols (напр. `forum`, `arrow_back`). 33 уникальных. |
| `fill` | 0 \| 1 | Ось FILL: 0 = outlined (`name.svg`), 1 = filled (`name-fill.svg`). |
| `svg` | path | Относительный путь к файлу (`svg/forum-fill.svg`). |
| `group` | enum | `navigation` \| `actions` \| `status` \| `fileTypes` \| `emptyStates` \| `misc`. |
| `use` | string | Назначение (напр. «Chats tab — selected (filled)»). |

**Counts (реконсилированы, R2):**
- Файлов на диске: **37**. Записей в `icons.json` (references): **38**. Уникальных имён (ligatures): **33**. Уникальных svg-путей в `icons.json`: **35**.
- 2 файла на диске **не упомянуты** в `icons.json` — outlined-варианты `flashlight_on.svg`, `send.svg` (используется только их filled-форма). Бандлятся (полнота), в реестр `NoxIcons` не входят.

**Filled/outlined-пары** (оба варианта присутствуют): `forum`, `settings`, `send`*, `flashlight_on`* (`*` — outlined-вариант на диске, но не в `icons.json`).

**Подменённые имена** (svg-пакет не содержит оригинал): `music_note` (= audio, ориг. `audiotrack`), `draft` (= прочий файл, ориг. `insert_drive_file`). Flutter-константы при этом — `Icons.music_note` / `Icons.insert_drive_file`.

**Validation / инварианты:**
- Все 37 файлов присутствуют в `assets/svg/icons/` и резолвятся (нет `asset not found`).
- Каждый SVG: `viewBox="0 -960 960 960"`, единственный `<path fill="currentColor">` — перекрашиваемый, цвет не зашит.
- Стиль набора: Rounded, weight 400, opticalSize 24, grade 0, defaultSizeDp 24.

### 1.2 BrandLogo

| Поле | Значение |
|---|---|
| `path` | `assets/png/logo.png` (из `nox-assets/brand/logo.png`) |
| `format` / `dims` | PNG, 200×200, opaque |
| `usage` | Splash 1.1 — 168×168 на `brand/canvasDark` (#0C2424) |
| `status` | `placeholder-raster` (финальный вектор — pending, вне scope) |

**Excluded**: `logo-reference.png` (reference-only moodboard) — **не** бандлится. **Pending (вне scope)**: финальный вектор логотипа (SVG), launcher app-icon.

### 1.3 Illustration (empty-state placeholders)

Источник: `nox-assets/illustrations/` → `assets/svg/illustrations/`. Все — SVG-плейсхолдеры, читаемые на light и dark (прозрачный фон, тонкий контур + brand-акценты).

| `id` | path | Экран | Fallback-иконка (если нет арта) |
|---|---|---|---|
| `empty-chats` | `assets/svg/illustrations/empty-chats.svg` | 5.1 no chats | `forum_outlined` |
| `empty-messages` | `assets/svg/illustrations/empty-messages.svg` | 5.2 no messages | `chat_bubble_outline` |
| `empty-files` | `assets/svg/illustrations/empty-files.svg` | 5.4 no files | `folder_open` |

**Status**: `placeholder` (финальный арт — pending, вне scope). Fallback-иконки берутся из набора Icon (§1.1, группа `emptyStates`).

### 1.4 Font

Источник: внешний (Google Fonts, Apache-2.0) → `assets/fonts/`. Объявление: `pubspec.yaml` → `fonts:`.

| `family` | `weight` | Файл | Назначение |
|---|---|---|---|
| `Roboto` | 400 | `Roboto-Regular.ttf` | Body/Title (w400-роли тайпскейла) |
| `Roboto` | 500 | `Roboto-Medium.ttf` | titleMedium/labelLarge/labelMedium (w500) |
| `Roboto` | 700 | `Roboto-Bold.ttf` | Вордмарк NOX (Bold) |
| `Roboto Mono` | 400 | `RobotoMono-Regular.ttf` | Отображение `Your ID` / ключей |

**Validation / инварианты:**
- Имена `family` **точно** = строки в `nox_text_theme.dart` (`'Roboto'`, `'Roboto Mono'`) — иначе silent fallback.
- Лицензия/источник зафиксированы (`assets/fonts/README.md`, Apache-2.0).

---

## 2. Token entities (9 сетов)

Источник истины: `docs/design/system/nox-handoff/tokens/*.tokens.json` (W3C DTCG) + сгенерированный Dart `nox-handoff/flutter/nox_*.dart`. В коде: `lib/design/theme/nox_*.dart` (синхронизированные копии). Статус: уже заведены; фича верифицирует и закрывает пробелы.

### 2.1 Color (light / dark) — `nox_color_scheme.dart`
`const ColorScheme noxLightScheme` / `noxDarkScheme` — полные M3-роли (не `fromSeed`; роли — точные значения токенов; seed-teal `#12B4B4` — лишь отправная точка). Источник: `color.light.tokens.json` / `color.dark.tokens.json`. **Статус: совпадает с хендофом → verify-only.**

### 2.2 Typography — `nox_text_theme.dart` (+ размеры в `app_text_style_tokens.dart`)
`const TextTheme noxTextTheme`, семейство `Roboto` / `Roboto Mono`; `height = lineHeightPx / fontSize`.

| Роль | fontSize | lineHeight (px) | height (ratio) | weight |
|---|---|---|---|---|
| `displaySmall` | 36 | 44 | 1.222 | w400 |
| `headlineSmall` | 24 | 32 | 1.333 | w400 |
| `titleLarge` | 22 | 28 | 1.273 | w400 |
| `titleMedium` | 16 | 24 | 1.500 | w500 |
| `bodyLarge` | 16 | 24 | 1.500 | w400 |
| `bodyMedium` | 14 | 20 | 1.429 | w400 |
| `labelLarge` | 14 | 20 | 1.429 | w500 |
| `labelMedium` | 12 | 16 | 1.333 | w500 |
| `labelSmall` | 11 | 16 | 1.455 | w500 |

**Размеры шрифта (`AppTextStyleTokens`)** — пробел, закрываемый фичей: 9 color-injecting `.sp`-фабрик с теми же `fontSize`/`fontWeight`/`letterSpacing` (без `height`, без `fontFamily`). См. contracts §2.

### 2.3 Spacing — `nox_tokens.dart` → `NoxSpacing` (фикс) + `app_spacing_tokens.dart` → `AppSpacingTokens` (отзывчивый)
Фикс (4dp-сетка): `s1=4, s2=8, s3=12, s4=16, s6=24, s8=32`. Отзывчивые (`.w/.h`-mean): `s4,s8,s12,s16,s24,s28,s32`. **Статус: фикс совпадает по значениям (отличие — форматирование, R6).**

### 2.4 Shape / radius — `nox_tokens.dart` → `NoxRadius`
`none=0, xs=4, s=8, m=12, l=16, xl=28` + helper `bubble(isOwn)` (асимметричный радиус пузыря сообщения). **Verify.**

### 2.5 Elevation — `nox_tokens.dart` → `NoxElevation`
`level0=0, level1=1, level2=3, level3=6` (dp). **Verify.**

### 2.6 Motion — `nox_tokens.dart` → `NoxDuration` / `NoxEasing`
Длительности: `splashIn=400, push=300, tabFade=150, snackbarIn=150, sheet=300` (ms). Easings: именованные `Cubic(...)` из `motion.tokens.json`. **Verify.**

### 2.7 Brand-fixed — `nox_brand.dart` → `NoxBrand`
Не зависят от темы (продуктовые константы): splash-фон `#0C2424` (canvasDark), QR-поверхность `#FFFFFF`, QR-чернила `#0C0C0C`; brand white `#FAFAFA`, gold `#F4C20C`, seed teal `#12B4B4`. Источник: `brand.tokens.json`. **Verify.**

### 2.8 Avatars — `nox_brand.dart`
Детерминированная 8-цветовая палитра + `noxAvatarColor(name)` (хэш имени → цвет) + `noxInitials(name)` (1–2 инициала, всегда белые). Источник: `avatars.tokens.json`. **Verify.**

### 2.9 (Метаданные load-order) — `tokens/$metadata.json`
Порядок загрузки токен-сетов (brand/avatars — mode-independent; color.light/dark — два режимных сета). Референс для будущего пайплайна (вне scope).

---

## 3. Производные кодовые сущности (вводятся фичей)

### 3.1 `NoxIcons` (`lib/design/nox_icons.dart`) — NEW
Семантический реестр: именованные геттеры (по глифу+FILL: `forum`/`forumFill`, …) → flutter_gen-аксессоры `Assets.svg.icons.*`. Несёт метаданные (FILL/`use`/группа) в doc-комментариях; **не** дублирует строки путей. Покрывает 35 используемых svg; 2 неиспользуемых outlined — вне реестра. Контракт — contracts §1.

### 3.2 `AppTextStyleTokens` (`app_text_style_tokens.dart`) — UPDATED
Заменяет ad-hoc `body/title/caption` на 9 ролей (§2.2). Контракт — contracts §2.

### 3.3 `Assets` (`lib/design/gen/assets.gen.dart`) — GENERATED
flutter_gen: `Assets.png.logo`, `Assets.svg.icons.*`, `Assets.svg.illustrations.*`. Gitignored, воспроизводится кодогеном.

### 3.4 `AppImagesTokens` — REMOVED
Удаляется (R8); единственный канал путей — flutter_gen.

---

## 4. Связи

```
icons.json ──(метаданные)──► NoxIcons ──(ссылается)──► Assets.svg.icons.*  ──► assets/svg/icons/*.svg
illustrations ─────────────────────────► Assets.svg.illustrations.*       ──► assets/svg/illustrations/*.svg
logo.png ───────────────────────────────► Assets.png.logo                  ──► assets/png/logo.png
fonts (pubspec fonts:) ◄── семейство ──── noxTextTheme ('Roboto'/'Roboto Mono')
tokens/*.tokens.json ──(источник истины)──► nox-handoff/flutter/nox_*.dart ──(копия)──► lib/design/theme/nox_*.dart
noxTextTheme (sizes) ◄── те же fontSize/weight ── AppTextStyleTokens (responsive .sp)
```

## 5. Сводные инварианты согласованности (проверяются в quickstart/тестах)

1. 37/37 иконок резолвятся; 0 битых путей среди всех аксессоров и токенов картинок.
2. `family`-имена шрифтов = строки `noxTextTheme`; объявлены начертания 400/500/700 (Roboto) + 400 (Mono).
3. 9/9 токен-сетов присутствуют и согласованы с `nox-handoff/`; репрезентативные значения проходят регрессионный тест (R6).
4. `AppTextStyleTokens` перечисляет 9 ролей шкалы; `AppImagesTokens` отсутствует.
5. `flutter analyze` — 0 ошибок; кодоген — один проход; сгенерированные файлы не редактированы руками.
6. 0 виджетов/экранов добавлено; затронутые разделы блюпринта согласованы (R9).
