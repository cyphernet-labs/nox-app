# Tasks: Инициализация дизайн-системы в `lib/design` (всё, кроме виджетов)

**Branch**: `002-design-system-init` | **Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

**Организация**: задачи сгруппированы по user story (US1→US4 из `spec.md`). Авторитет «как» — блюпринт `docs/blueprints/mobile/06-theming.md` (+ `01`/`10`); источник истины значений — токены `docs/design/system/nox-handoff/tokens/*.tokens.json` (проза `design-system.md` при расхождении — НЕ источник). Пути файлов канонизированы по `data-model.md §0`. **Тесты включены** (затребованы спекой: FR-024/SC-007/SC-010). **Виджеты — вне объёма.**

## Формат

`- [ ] [ID] [P?] [Story?] Описание + путь к файлу` — `[P]` = можно параллельно (разные файлы, нет незавершённых зависимостей); `[USx]` — только в фазах user story.

---

## Phase 1: Setup (общая инфраструктура)

- [x] T001 Добавить зависимость `material_symbols_icons` в `pubspec.yaml` (раздел `dependencies`) — иконочный набор Material Symbols Rounded (research §A).
- [x] T002 Положить файлы шрифта `Roboto Mono` в `assets/fonts/` и объявить блок `flutter.fonts:` (family `Roboto Mono`) в `pubspec.yaml`; подтвердить декларацию `assets/fonts/` (research §B, FR-010, SC-005). Зависит от: —.
- [x] T003 Выполнить `fvm flutter pub get` (подтянуть `material_symbols_icons` + шрифты). Зависит от: T001, T002.
- [x] T004 Прогнать кодоген `fvm dart run build_runner build --delete-conflicting-outputs` — `flutter_gen` подхватывает шрифты/ассеты в `lib/design/gen/assets.gen.dart`. Зависит от: T003.

---

## Phase 2: Foundational (блокирующие предпосылки — ДО user stories)

- [x] T005 Сверить сгенерированный слой `lib/design/theme/nox_*.dart` (`nox_color_scheme`/`nox_text_theme`/`nox_tokens`/`nox_brand`) с `docs/design/system/nox-handoff/tokens/*.tokens.json`; зафиксировать правило регенерации (руками не править, регенерировать из токенов) комментарием-баннером в файлах (research §G/§H, data-model §0). **Блокирует все US.**
- [x] T006 [P] Подтвердить wiring `flutter_screenutil` (`Constants.designSize`, `ScreenUtilInit`) в `lib/general/constants.dart` как фундамент токенов spacing/typography (data-model §6). **Блокирует US1/US3 spacing-токены.**

**Контрольная точка**: токен-точный генерируемый слой + screenutil подтверждены — можно начинать user stories.

---

## Phase 3: User Story 1 — Канонический токенизированный фундамент темы (Priority: P1) 🎯 MVP

**Цель**: единый `ColorScheme` (light+dark) + типошкала + токены формы/высоты/отступов/движения + бренд, всё из токенов `nox-handoff`; тема собирается и переключается `themeMode` без потери ролей и без хардкода.

**Independent test**: `AppTheme.light()/dark()` строятся; все M3-роли заданы; значения = токенам; light↔dark перерисовывает.

### Tests (US1)

- [x] T007 [P] [US1] Тест сборки темы: `AppTheme.light()`/`AppTheme.dark()` собираются, все M3-роли `ColorScheme` не-null (SC-002) — `test/design/theme_build_test.dart`.
- [x] T008 [P] [US1] Тест верности токенам: значения `noxLightScheme`/`noxDarkScheme` совпадают с `color.{light,dark}.tokens.json` (нулевой дрейф; FR-001, SC-003) — `test/design/color_scheme_tokens_test.dart`.

### Implementation (US1)

- [x] T009 [US1] Политика шрифтов в `lib/design/theme/nox_text_theme.dart`: sans — платформенно-нативный (убрать хардкод `fontFamily: 'Roboto'`); mono = бандленный `Roboto Mono` (`noxMonoFamily`) (research §B, data-model §3, FR-002, FR-010). Зависит от: T002.
- [x] T010 [US1] Добавить wordmark-стиль «NOX» (база `titleLarge`, weight 700, letter-spacing +0.12em) в `lib/design/theme/nox_text_theme.dart` (data-model §3, FR-005). Зависит от: T009 (тот же файл).
- [x] T011 [US1] Собрать/уточнить `AppTheme.light()/dark()` (примитивы) в `lib/design/theme/app_theme.dart`: `colorScheme` + `textTheme` + готовность `themeMode` (data-model §8, FR-006). Зависит от: T009, T010.
- [x] T012 [P] [US1] Сверить токен-классы `lib/design/theme/nox_tokens.dart` (`NoxSpacing`/`NoxRadius`(+bubble)/`NoxElevation`/`NoxDuration`/`NoxEasing`) с `{spacing,shape,elevation,motion}.tokens.json` (data-model §5, FR-003).
- [x] T013 [P] [US1] Сверить `NoxBrand` (бренд-фиксы splash/QR + бренд-палитра) в `lib/design/theme/nox_brand.dart` с `brand.tokens.json` (data-model §7, FR-004).

**Контрольная точка US1**: тема light/dark из токенов, шрифты и wordmark на месте — MVP дизайн-фундамента готов и независимо тестируем.

---

## Phase 4: User Story 2 — Семантические роли и component-сабтемы (Priority: P2)

**Цель**: полный token-driven `AppColors` + component-сабтемы `ThemeData` (§9), чтобы будущие виджеты наследовали NOX-стиль без хардкода.

**Independent test**: `context.appColors` отдаёт полный набор ролей; стоковые M3-компоненты под темой получают NOX-стиль; brand-fixed component-токены доступны.

### Tests (US2)

- [x] T014 [P] [US2] Тест: `context.appColors` отдаёт полный набор доп-ролей (не skeleton), значения из токенов — `test/design/app_colors_test.dart`.

### Implementation (US2)

- [x] T015 [US2] Развернуть `AppColors` ThemeExtension в `lib/design/theme/app_colors.dart` до полного token-driven набора (timestamp@70%, `dividerSubtle`, `surfaceMuted`, disabled @12%/@38%, `dragHandle`@40%, scanner-роли и др. по research §D); убрать ad-hoc литералы (data-model §2, FR-007).
- [x] T016 [P] [US2] Завести `NoxComponentTokens` (`lib/design/theme/nox_component_tokens.dart`) — brand-fixed §9.9/§9.10 (QR scanner mask@55%/reticle/instruction, QR surface/ink) (data-model §9, FR-009 NEW).
- [x] T017 [US2] Сконфигурировать component-сабтемы `ThemeData` в `lib/design/theme/app_theme.dart` из токенов/§9 (`CardTheme`/`FilledButtonTheme`/`TextButtonTheme`/`AppBarTheme`/`SnackBarTheme`/`DialogTheme`/`NavigationBarTheme`/`NavigationRailTheme`/`SegmentedButtonTheme`/`SwitchTheme`/`SearchBarTheme` и др.; референс — handoff `nox_theme.dart`) (data-model §8, FR-008). Зависит от: T011, T015, T016.

**Контрольная точка US2**: вся темизация (примитивы + семантика + сабтемы) завершена; виджеты не написаны, но стиль готов к наследованию.

---

## Phase 5: User Story 3 — Сквозные non-widget-фундаменты (Priority: P3)

**Цель**: иконки + реестр + карта типов файлов, форматтеры дат, microcopy, аватары, asset-реестр, overlay-канон.

**Independent test**: каждый фундамент присутствует и соответствует дизайн-корпусу (иконки рендерятся; карта типов покрывает §8; лестницы дат верны; аватар детерминирован).

### Tests (US3)

- [x] T018 [P] [US3] Тест: карта «тип файла → IconData» покрывает §8-набор + дефолт для неизвестного типа — `test/design/file_type_icon_test.dart`.
- [x] T019 [P] [US3] Тест: лестницы `DateFormatter` (relative + day-separator) дают форматы из `overview.md`/`design-system.md` — `test/general/date_formatter_test.dart`.
- [x] T020 [P] [US3] Тест: детерминизм аватара (палитра/хеш/инициалы/`forum`-fallback) против `design-system.md` §2.5 — `test/design/avatar_test.dart`.

### Implementation (US3)

- [x] T021 [P] [US3] Завести реестр `NoxIcons` + карту «тип файла → IconData» (с дефолтом) на `material_symbols_icons` в `lib/design/nox_icons.dart` (data-model §10, FR-011). Зависит от: T003.
- [x] T022 [P] [US3] Дополнить `lib/general/formatters/date_formatter.dart` лестницами относительного времени (список чатов) и разделителя дня (ленты) (data-model §14, FR-012).
- [x] T023 [P] [US3] Добавить сетевые/offline microcopy-строки (EN) в `lib/general/text_constants.dart` (включая «pull to refresh» для списка чатов) (data-model §15, FR-013).
- [x] T024 [P] [US3] Asset-реестр через `flutter_gen` (`lib/design/gen/assets.gen.dart`) + Material-icon fallback для непоставленных иллюстраций/лого (data-model §11, FR-015). Зависит от: T004.
- [x] T025 [P] [US3] Глобальное применение overlay-канона (`SystemChrome.setSystemUIOverlayStyle` по `Brightness`) + сверка `lib/design/app_overlay_style_tokens.dart` (data-model §12, FR-016; тонкий глобальный hook в `AppRoot`, не виджет).
- [x] T026 [P] [US3] Сверить фундамент генерируемого аватара (`noxAvatarPalette`/`noxAvatarIndex`/`noxAvatarColor`/`noxInitials`) в `lib/design/theme/nox_brand.dart` с §2.5 (data-model §7, FR-014).

**Контрольная точка US3**: иконки/форматтеры/microcopy/аватары/ассеты/overlay — все сквозные фундаменты на месте.

---

## Phase 6: User Story 4 — Единый источник истины и гигиена (Priority: P4)

**Цель**: один канонический канал на роль, нулевой дрейф, выровненные обёртки, зафиксированный источник истины.

**Independent test**: нет двух параллельных классов с одной ролью; значения = токенам; авторитетный handoff один.

### Implementation (US4)

- [x] T027 [P] [US4] Сделать `AppSpacingTokens` единым каноническим spacing-каналом; `NoxSpacing` оставить только под `minTapTarget`/`screenPadding` (`lib/design/app_spacing_tokens.dart` + `nox_tokens.dart`) (data-model §6, FR-018, SC-006).
- [x] T028 [P] [US4] Свернуть `AppImagesTokens` в `flutter_gen` (единый канал ассетов) либо ретайрнуть `lib/design/app_images_tokens.dart` (data-model §11, FR-018, SC-006).
- [x] T029 [P] [US4] Выровнять `AppTextStyleTokens` под M3-шкалу `noxTextTheme` (`lib/design/app_text_style_tokens.dart`) (data-model §4, FR-019).
- [x] T030 [P] [US4] Поправить устаревшую прозу `docs/design/spec/design-system.md` §2.3 (dark `outlineVariant` #3F4948→#4E5B58 по токену; surface-container ярусы) — **док-фикс, не код** (research §G, FR-017).
- [x] T031 [P] [US4] Перенести FILL-axis `icons.md` из `docs/design/system/nox-handoff-2/` в `docs/design/system/nox-handoff/spec/`; удаление дубликата `nox-handoff-2/` — отдельным change-set (research §I, FR-020).
- [x] T032 [US4] Обновить блюпринты `docs/blueprints/mobile/06-theming.md` (docs-in-sync: override §3 «component-сабтемы заводятся сейчас», источник истины = токены, правило регенерации) **и `docs/blueprints/mobile/10-code-templates.md` §16b** (устаревший шаблон `ThemeData.light().copyWith` → реальная сборка темы через `noxLightScheme` + component-сабтемы) (FR-021, SC-009, plan Constitution III).

**Контрольная точка US4**: дизайн-слой без дублей и дрейфов, источник истины зафиксирован.

---

## Phase 7: Polish & Cross-Cutting

- [ ] T033 [P] A11y: автотесты контраста пар роль/фон `ColorScheme` (≥4.5:1 body, ≥3:1 large/icons) + timestamp 70% — `test/design/contrast_test.dart` (data-model §16, FR-024/SC-010).
- [ ] T034 [P] Verification отсутствия хардкода стилей вне токенного слоя (grep `Color(`/`EdgeInsets`/`TextStyle(`/`Duration(` вне `lib/design/theme/*`, `app_colors.dart`, `nox_component_tokens.dart`, токен-файлов) (FR-022/SC-004); + сверка границы «никаких виджетов» (FR-023) — ни одного нового продуктового виджета в change-set.
- [ ] T035 Code-gate: codegen (1 прогон) → `fvm dart format -l 140` изменённых → `fvm flutter analyze` (0 ошибок) → `fvm flutter test` (затронутые) (SC-008). Зависит от: все предыдущие.
- [ ] T036 Прогон quickstart-валидации `specs/002-design-system-init/quickstart.md` (тема→контраст→шрифты/иконки→gate) (SC-001..SC-010). Зависит от: T035.

---

## Зависимости и порядок

- **Setup (T001–T004)** → **Foundational (T005–T006)** → user stories.
- **US1 (P1)** не зависит от US2–US4 — это MVP дизайн-фундамента.
- **US2 (P2)** строится на теме US1 (T017 зависит от T011/T015/T016).
- **US3 (P3)** в основном независим (иконки/форматтеры/microcopy/аватары/ассеты/overlay — разные файлы); зависит лишь от Setup (T003/T004).
- **US4 (P4)** — гигиена поверх готового слоя; может идти после US1–US3.
- **Polish (T033–T036)** — после соответствующих сторy; T035/T036 — финальный gate, после всего.

## Параллельные возможности

- Setup: T001→T002 последовательно (один `pubspec.yaml`), затем T003→T004.
- US1: `[P]` T007/T008 (тесты), T012/T013 (разные файлы); T009→T010→T011 последовательно (общие файлы/зависимость).
- US2: T015 и T016 `[P]` (разные файлы), затем T017.
- US3: T018/T019/T020 (тесты) и T021–T026 — почти все `[P]` (разные файлы).
- US4: T027–T031 `[P]` (разные файлы), затем T032.
- Polish: T033/T034 `[P]`.

## Стратегия реализации

- **MVP = User Story 1** (Phase 1–3): токенизированная тема light/dark из `nox-handoff` со шрифтами и wordmark. Самостоятельно ценно и тестируемо.
- Далее инкрементально: US2 (полная темизация со сабтемами) → US3 (сквозные фундаменты) → US4 (гигиена/SSOT) → Polish (контраст-тесты, no-hardcode, gate, quickstart).
- Каждая US — независимо тестируемый срез; виджеты не реализуются ни на одном шаге.
