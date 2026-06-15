---
description: "Список задач — 002-design-system-assets"
---

# Задачи: Завести дизайн-систему — ассеты, токены и шрифты

**Вход**: дизайн-документы из `specs/002-design-system-assets/`

**Предпосылки**: plan.md, spec.md, research.md, data-model.md, contracts/design-system-api.md, quickstart.md

**Тесты**: включены намеренно — фича верификационная по сути (quickstart S1–S6, research R6 предписывает `tokens_sync_test.dart`, FR-016 требует зелёных тестов). Тесты — механизм приёмки, не «padding».

**Организация**: по user stories (spec.md). Все пути — относительно корня репозитория. Команды — FVM (`docs/blueprints/mobile/12-dev-commands.md`).

## Формат: `[ID] [P?] [Story?] Описание`

- **[P]**: можно параллелить — разные файлы, нет зависимостей от *незавершённых* задач. Тест-таски `[P]` идут параллельно задачам *других* историй, но внутри своей истории — после её impl-задач (см. «Внутри истории» / «Параллельные возможности»).
- **[Story]**: `[US1]`…`[US5]` — только в фазах пользовательских историй.

---

## Фаза 1: Подготовка (общая инфраструктура)

**Назначение**: структура каталогов ассетов.

- [x] T001 [P] Создать подкаталоги ассетов `assets/fonts/`, `assets/svg/icons/`, `assets/svg/illustrations/` (временный `.gitkeep` — только там, где каталог иначе остался бы пустым до появления файлов)

---

## Фаза 2: Фундамент (блокирующие предпосылки)

**Назначение**: общая декларация ассетов в `pubspec.yaml`, на которую опираются истории заведения ассетов (US1, US3) и flutter_gen. **⚠️ Блокирует US1/US3.**

- [x] T002 Обновить `pubspec.yaml` `flutter > assets:` — перечислить `assets/png/`, `assets/svg/icons/`, `assets/svg/illustrations/`, `assets/animation/` (заменив «голые» `assets/` и `assets/svg/`), в `pubspec.yaml`
- [x] T003 Проверить конфиг `flutter_gen` в `pubspec.yaml` для этой фичи (`output: lib/design/gen/`, `integrations.flutter_svg: true`, `fonts.enabled: false`, `line_length: 140`) и подтвердить, что `.gitignore` по-прежнему игнорирует `lib/design/gen/` — правок не ожидается, зафиксировать при наличии

**Контрольная точка**: каталоги и декларация ассетов готовы — заведение ассетов может начинаться.

---

## Фаза 3: Пользовательская история 1 — Иконки заведены (Приоритет: P1) 🎯 MVP

**Цель**: все 37 SVG Material Symbols в бандле + type-safe доступ (flutter_gen) + семантический реестр `NoxIcons`.

**Независимый тест**: `ls assets/svg/icons/*.svg | wc -l` → 37; `NoxIcons.*` и `Assets.svg.icons.*` резолвятся; тест резолва зелёный (нет `asset not found`). (quickstart S1)

### Реализация Пользовательской истории 1

- [x] T004 [US1] Скопировать все 37 SVG **вербатим** (вкл. `*-fill.svg` и 2 неиспользуемых outlined `flashlight_on.svg`/`send.svg`) из `docs/design/system/nox-assets/icons/svg/` в `assets/svg/icons/`
- [x] T005 [US1] Прогнать кодоген, чтобы перегенерировать `lib/design/gen/assets.gen.dart` и появились аксессоры `Assets.svg.icons.*`: `fvm dart run build_runner build --delete-conflicting-outputs` (зависит от T002, T004)
- [x] T006 [US1] Создать `lib/design/nox_icons.dart` — `abstract final class NoxIcons` с именованными геттерами (глиф+FILL: `forum`/`forumFill`, `settings`/`settingsFill`, `sendFill`, `flashlightOn`/`flashlightOff`, …), возвращающими flutter_gen-аксессоры `Assets.svg.icons.*` (без сырых строк путей); doc-комментарий к каждому — FILL + `use` + группа из `icons.json`; покрыть 35 используемых svg, отметить, что 2 неиспользуемых outlined исключены (contracts §1, data-model §1.1)

### Тест Пользовательской истории 1

- [x] T007 [P] [US1] Добавить `test/design/icons_resolution_test.dart` — проверить, что 37 файлов есть в `assets/svg/icons/`, каждый геттер `NoxIcons` резолвится в существующий ассет, сходится реконсиляция счётчиков (35 used + 2 outlined), **и** каждый забандленный `assets/svg/icons/*.svg` несёт `fill="currentColor"` без зашитого `fill`/цвета (закрывает FR-003 + Acceptance US1-#2, инвариант data-model §1.1)

**Контрольная точка**: US1 полностью функциональна и тестируема независимо.

---

## Фаза 4: Пользовательская история 2 — Шрифты типографики заведены (Приоритет: P1)

**Цель**: `Roboto` 400/500/700 + `Roboto Mono` 400 в бандле и объявлены; типографика рендерится заданными семействами без silent fallback.

**Независимый тест**: `ls assets/fonts/*.ttf` → 4 файла; `pubspec.yaml` объявляет семейства/веса; имена семейств = строки `nox_text_theme.dart`. (quickstart S2)

### Реализация Пользовательской истории 2

- [x] T008 [US2] Дотянуть статические `.ttf` (Apache-2.0, Google Fonts) и положить в `assets/fonts/`: `Roboto-Regular.ttf` (400), `Roboto-Medium.ttf` (500), `Roboto-Bold.ttf` (700), `RobotoMono-Regular.ttf` (400) — research R1
- [x] T009 [P] [US2] Добавить `assets/fonts/README.md` с фиксацией источника, версии и лицензии Apache-2.0 для обоих семейств
- [x] T010 [US2] Добавить блок `fonts:` в `pubspec.yaml` — семейство `Roboto` (ассеты 400/500/700) + семейство `Roboto Mono` (ассет 400) — имена семейств **точно** `Roboto` / `Roboto Mono`, совпадающие с `nox_text_theme.dart` (`_sans` / `noxMonoFamily`); в `pubspec.yaml` (зависит от T008)

### Тест Пользовательской истории 2

- [x] T011 [P] [US2] Добавить `test/design/fonts_declaration_test.dart` — проверить, что 4 `.ttf` существуют, `pubspec.yaml` объявляет оба семейства с весами 400/500/700 (Roboto) и 400 (Roboto Mono), а объявленные строки семейств равны тем, что в `lib/design/theme/nox_text_theme.dart`

**Контрольная точка**: US2 функциональна и тестируема независимо.

---

## Фаза 5: Пользовательская история 3 — Бренд и иллюстрации без битых ссылок (Приоритет: P2)

**Цель**: `logo.png` + 3 иллюстрации в бандле; пути картинок резолвятся; `AppImagesTokens` удалён.

**Независимый тест**: `Assets.png.logo` + `Assets.svg.illustrations.*` резолвятся; `logo-reference.png` не забандлен; `grep AppImagesTokens lib/` пусто. (quickstart S3)

### Реализация Пользовательской истории 3

- [x] T012 [P] [US3] Скопировать `docs/design/system/nox-assets/brand/logo.png` в `assets/png/logo.png` (`logo-reference.png` **не** копировать)
- [x] T013 [P] [US3] Скопировать 3 иллюстрации SVG **вербатим** (`empty-chats.svg`, `empty-messages.svg`, `empty-files.svg`) из `docs/design/system/nox-assets/illustrations/` в `assets/svg/illustrations/`
- [x] T014 [P] [US3] Удалить `lib/design/app_images_tokens.dart` (внешних потребителей нет — подтверждено; flutter_gen — единственный канал, research R8)
- [x] T015 [US3] Прогнать кодоген, чтобы перегенерировать `lib/design/gen/assets.gen.dart` и появились `Assets.png.logo` + `Assets.svg.illustrations.*`: `fvm dart run build_runner build --delete-conflicting-outputs` (зависит от T002, T012, T013)

### Тест Пользовательской истории 3

- [x] T016 [P] [US3] Добавить `test/design/images_resolution_test.dart` — проверить, что `Assets.png.logo` и 3 `Assets.svg.illustrations.*` резолвятся в существующие ассеты, `assets/png/logo-reference.png` отсутствует, а `lib/design/app_images_tokens.dart` больше не существует

**Контрольная точка**: US3 функциональна и тестируема независимо.

---

## Фаза 6: Пользовательская история 4 — Полнота и консистентность токенов (Приоритет: P2)

**Цель**: 9 токен-сетов согласованы с `nox-handoff/`; `AppTextStyleTokens` — полная 9-ролевая шкала размеров шрифта.

**Независимый тест**: diff `lib/design/theme/nox_*.dart` vs хендоф (значения совпадают); `AppTextStyleTokens` = 9 ролей; brand-fixed/avatars на месте. (quickstart S4)

### Реализация Пользовательской истории 4

- [x] T017 [US4] Проверить, что `lib/design/theme/nox_color_scheme.dart`, `nox_text_theme.dart`, `nox_brand.dart` совпадают по значениям с `docs/design/system/nox-handoff/flutter/`, и пересинхронизировать `lib/design/theme/nox_tokens.dart` к значениям источника (значения уже равны; согласовать только форматирование, `dart format -l 140`) — research R6
- [x] T018 [US4] Обновить `lib/design/app_text_style_tokens.dart` — заменить `body`/`title`/`caption` на 9 color-injecting `.sp`-фабрик M3-ролей (`displaySmall` 36/w400, `headlineSmall` 24/w400, `titleLarge` 22/w400, `titleMedium` 16/w500, `bodyLarge` 16/w400, `bodyMedium` 14/w400, `labelLarge` 14/w500, `labelMedium` 12/w500, `labelSmall` 11/w500), с `letterSpacing`, **без** `height`, **без** `fontFamily` (contracts §2, research R7)

### Тесты Пользовательской истории 4

- [x] T019 [P] [US4] Добавить `test/design/tokens_sync_test.dart` — ассерты репрезентативных значений: spacing `s4==16`, radius `xl==28`, elevation `level2==3`, duration `push==300ms`, `bodyMedium.fontSize==14`, `titleMedium.fontWeight==w500`, brand splash `#0C2424` / QR surface `#FFFFFF` / QR ink `#0C0C0C`, длина палитры аватаров `8` (research R6)
- [x] T020 [P] [US4] Добавить `test/design/text_style_tokens_test.dart` — проверить, что `AppTextStyleTokens` отдаёт 9 ролей с верными `fontSize`/`fontWeight`/`letterSpacing` (производно от `noxTextTheme`) и не задаёт `height`

**Контрольная точка**: US4 функциональна и тестируема независимо.

---

## Фаза 7: Пользовательская история 5 — Единый канал ассетов и синхрон блюпринта (Приоритет: P3)

**Цель**: flutter_gen — единственный канал путей; блюпринт `06-theming.md` §0/§1/§5/§7 отражает реальность.

**Независимый тест**: нет сырых `'assets/'`-строк в `lib/` (вне gen); блюпринт §0/§1/§5/§7 обновлён. (quickstart S5)

### Реализация Пользовательской истории 5

- [x] T021 [US5] Обновить `docs/blueprints/mobile/06-theming.md` §0 (файловое дерево) — добавить `nox_icons.dart`, убрать `app_images_tokens.dart`
- [x] T022 [US5] Обновить `docs/blueprints/mobile/06-theming.md` §1 (семейства шрифтов теперь забандлены) и §5 (`AppTextStyleTokens` = 9-ролевая шкала; footnote на строке ~443 «Семейства бандлятся (или берётся платформенный дефолт)» → теперь забандлены `Roboto` 400/500/700 + `Roboto Mono` 400)
- [x] T023 [US5] Обновить `docs/blueprints/mobile/06-theming.md` §7 (ассеты «оба канала» разрешено: `AppImagesTokens` удалён, flutter_gen авторитетен; добавить реестр `NoxIcons` + заметку о забандленных иконках — иконки живут в §7 (картиночные ассеты), отдельного §8 для иконок нет) **и явно зафиксировать pending-ассеты как вне scope** (финальный вектор логотипа SVG, launcher app-icon, финальные иллюстрации — статус по `nox-assets/manifest.json`), чтобы FR-015 / SC-007 / Acceptance US3-#3 имели repo-visible запись, а не только прозу в tasks.md
- [x] T024 [P] [US5] Добавить `test/design/single_channel_guard_test.dart` (или CI grep-шаг) — проверить, что в `lib/` вне `lib/design/gen/` нет сырых строк-литералов `'assets/...'`, а символ `AppImagesTokens` отсутствует

**Контрольная точка**: US5 функциональна; блюпринт синхронен.

---

## Фаза 8: Полировка и сквозные задачи

**Назначение**: финальный гейт кода и валидация.

- [x] T025 Прогнать финальный одно-проходный кодоген `fvm dart run build_runner build --delete-conflicting-outputs` (перегенерирует `lib/design/gen/assets.gen.dart` со всеми ассетами)
- [x] T026 Отформатировать изменённые Dart-файлы `fvm dart format -l 140 $(git diff --name-only '*.dart')` (последовательно — после кодогена T025)
- [x] T027 Прогнать `fvm flutter analyze` — должно быть 0 ошибок (сгенерированные файлы руками не правятся)
- [x] T028 Прогнать `fvm flutter test test/design/` — все verification-тесты зелёные
- [x] T029 Выполнить сценарии `specs/002-design-system-assets/quickstart.md` S1–S6 и подтвердить каждый Expected-результат
- [x] T030 Scope guard — подтвердить, что 0 виджетов/UI-Kit/экранов добавлено (нет изменений в `lib/presentation/**`; `nox-handoff-2/flutter/widgets/*` не портирован) и `lib/design/gen/` остаётся gitignored; отметить Definition of Done в quickstart.md
- [x] T031 [P] Build-smoke — прогнать `fvm flutter build macos` (репрезентативный desktop-таргет), чтобы подтвердить, что забандленные шрифты/ассеты пакуются без ошибок; обосновывает SC-005 «сборка проходит на целевых платформах». Полный пер-платформенный рендер шрифтов (SC-003) в остальном покрыт существующими CI compile-smoke-джобами (Windows/Linux/macOS) + тестом деклараций/имён T011

---

## Зависимости и порядок выполнения

### Зависимости фаз

- **Подготовка (Фаза 1)**: без зависимостей — старт сразу.
- **Фундамент (Фаза 2)**: зависит от Подготовки — **блокирует US1 и US3** (декларация ассетов). US4 от неё не зависит; US2 — только через T010 (его правка `pubspec.fonts:` идёт после T002, тот же файл).
- **Пользовательские истории (Фазы 3–7)**: после Фундамента (для историй с ассетами). US4 (токены) независима от Фундамента; US2 (шрифты) независима, кроме T010 (общий `pubspec.yaml`). В остальном истории независимы друг от друга.
- **Полировка (Фаза 8)**: после всех нужных историй.

### Зависимости по историям

- **US1 (иконки, P1)**: нужен T002 (декларация ассетов). Независима от US2/US4/US5.
- **US2 (шрифты, P1)**: файлы шрифтов (T008/T009) независимы; блок `fonts:` (T010) правит общий `pubspec.yaml`, поэтому идёт после T002 (тот же файл, последовательно). Независима от других историй.
- **US3 (бренд/иллюстрации, P2)**: нужен T002. Удаление `AppImagesTokens` (T014) независимо от US1.
- **US4 (токены, P2)**: полностью независима (чистые Dart-файлы токенов).
- **US5 (канал/блюпринт, P3)**: лучше делать последней — её правки блюпринта §7/§0 описывают результаты US1 (`NoxIcons`) и US3 (удаление `AppImagesTokens`); guard T024 предполагает, что удаление из US3 уже произошло.

### Внутри истории

- Копирование ассетов → кодоген → код/реестр → тест.
- `pubspec.yaml` правят T002 (assets), затем T010 (fonts) — тот же файл, последовательно.
- `06-theming.md` правят T021→T022→T023 — тот же файл, последовательно.

### Параллельные возможности

- T001 — единственная в Подготовке.
- После T002 разные истории трогают **разные файлы**: копия иконок US1 (T004), копии US3 (T012/T013/T014), шрифты US2 (T008/T009), правки токенов US4 (T017/T018) → параллелятся разными разработчиками.
- Все тест-таски `test/design/*` (T007, T011, T016, T019, T020, T024) — `[P]` (разные файлы).
- Кодоген-таски (T005, T015, T025) трогают один сгенерированный файл → **не** параллельны; запускать последовательно / схлопнуть в финальный T025.

---

## Пример параллелизма: после Фундамента (T002)

```bash
# Разные разработчики / параллельные агенты, разные файлы:
Task: "T004 [US1] Скопировать 37 SVG-иконок в assets/svg/icons/"
Task: "T008 [US2] Положить Roboto/Roboto Mono .ttf в assets/fonts/"
Task: "T012 [US3] Скопировать logo.png в assets/png/"
Task: "T017 [US4] Проверить/пересинхронизировать токены nox_*.dart vs хендоф"
# Затем сойтись на одном прогоне кодогена (T025) перед тест-набором.
```

---

## Стратегия реализации

### Сначала MVP

P1 = **US1 (иконки)** 🎯 + **US2 (шрифты)**. Поставить Подготовку → Фундамент → US1 → US2, валидировать независимо (quickstart S1–S2). Это разблокирует все будущие экраны (иконки + типографика рендерятся как задумано).

### Инкрементальная поставка

1. Подготовка + Фундамент → проводка ассетов готова.
2. US1 (иконки) → валидировать S1 → 🎯 ядро MVP.
3. US2 (шрифты) → валидировать S2.
4. US3 (бренд/иллюстрации) → валидировать S3.
5. US4 (полнота токенов) → валидировать S4.
6. US5 (единый канал + синхрон блюпринта) → валидировать S5.
7. Полировка (кодоген/format/analyze/test/quickstart/scope-guard) → S6.

### Заметки

- `[P]` = разные файлы, без зависимостей от незавершённых задач. `[US#]` маппит задачу на user story из spec.md.
- Одного прогона кодогена достаточно при серийной сборке (схлопнуть T005/T015 в T025); пер-историйный кодоген — только при сборке историй в изоляции.
- Единственный внешний артефакт для дотягивания — 4 шрифтовых `.ttf` (Apache-2.0); остальное копируется из `docs/design/system/`.
- Правки блюпринта (US5) — часть этого change-set по Принципу III, не follow-up.
- Вне scope (не создавать): любой виджет/UI-Kit/примитив/экран; финальный вектор логотипа, launcher app-icon, финальные иллюстрации.
- Whole-project gate/command-таски (`build_runner`, `flutter analyze`, `flutter build`) намеренно path-less / project-scoped — они прогоняют весь пакет, а не один файл; правило «конкретный путь» — для файло-производящих задач.
