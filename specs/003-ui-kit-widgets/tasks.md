---
description: "Task list — UI-кит (003-ui-kit-widgets)"
---

# Tasks: UI-кит — библиотека виджетов представления

**Input**: Design documents from `specs/003-ui-kit-widgets/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/ui-kit-api.md`, `quickstart.md`

**Tests**: ВКЛЮЧЕНЫ — фича явно требует golden-тест **и** widget-тест на каждый новый виджет (`FR-013`/`FR-014`). Голден-тесты генерируются скиллом `/golden-test`, widget-тесты — `/widget-test`. Порядок: **реализация виджета → widget-тест → golden-тест** (golden-baseline требует уже отрендеренного виджета — это не TDD-first, а skill-driven; baseline пишется локально на M1 через `make golden-update`).

**Organization**: задачи сгруппированы по 4 user story из `spec.md` (US1 P1 → US4 P3) для независимой реализации/проверки.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: можно параллелить (разные файлы, нет зависимостей от незавершённых задач)
- **[Story]**: US1–US4; Setup/Foundational/Polish — без story-метки
- Пути — точные, относительно корня репо

## Path Conventions

Единый пакет `nox_app`. Виджеты — `lib/presentation/widgets/<group>/`; хелперы — `lib/presentation/helpers/`; тема — `lib/design/theme/`; лаунчер/галерея — `lib/presentation/pages/home_page/`, `lib/presentation/pages/ui_kit_page/`; тесты deep-mirror — `test/presentation/widgets/<group>/`, goldens — в `goldens/` рядом с тестом.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: подготовка окружения; новых зависимостей нет (`material_symbols_icons` **не** добавляется — R1).

- [x] T001 Подтвердить базлайн сборки: `fvm flutter pub get` + один прогон codegen `make generate` (`assets.gen.dart` актуален); убедиться, что `make gate` зелёный на текущем дереве (точка отсчёта).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: общая основа, без которой нельзя начать ни одну story.

**⚠️ CRITICAL**: блокирует все user stories.

- [x] T002 [P] Создать общий pump-хелпер `test/utils/pump_app.dart` (`ScreenUtilInit(designSize: Constants.designSize)` + `MaterialApp(theme: AppTheme.light(), darkTheme: AppTheme.dark(), themeMode)` + фикс `textScaler=1.0`), по `.claude/commands/widget-test.md`.
- [x] T003 [P] Расширить `lib/design/app_spacing_tokens.dart` недостающими шагами 4dp-сетки (`s2`,`s6`,`s10`,`s14`,`s20`, при необходимости `s56`), которые использует референс — без хардкода в виджетах (R2).
- [x] T004 [P] Добавить в `lib/general/text_constants.dart` дефолтную UI-микрокопи кита на English (`searchHint='Search'`, `composerHint='Message'`, `actionDismiss='Dismiss'`, `errorGeneralTitle`/`actionTryAgain` если отсутствуют) — `FR-012`.

**Checkpoint**: основа готова — можно начинать US1.

---

## Phase 3: User Story 1 — Фундамент: примитивы, тема stock-виджетов, generic state-виджеты (Priority: P1) 🎯 MVP

**Goal**: подключаемая тема (stock-виджеты выглядят как NOX без кастом-классов) + примитивы (иконка/спиннер/аватар/файл-глиф) + виджеты состояний загрузки/ошибки/пустоты.

**Independent Test**: подключить `AppTheme`, отрендерить набор stock-виджетов + примитивы + state-виджеты; `make gate` зелёный; goldens (l/d) и widget-тесты проходят (`quickstart §1–§2`).

### Примитивы

- [x] T005 [P] [US1] `FileType` enum + `noxFileIcon()`/`noxFileColor()` (→ `NoxIcons`/`NoxBrand`) в `lib/presentation/widgets/primitives/file_type.dart` (`FR-001` — App*-нейминг + enum без `Nox`).
- [x] T006 [P] [US1] `AppIconWidget` (SVG-глиф `NoxIcons` + `ColorFilter` + `fill`) в `lib/presentation/widgets/primitives/app_icon_widget.dart` (R1, `FR-004` — token-bindings).
- [x] T007 [US1] Widget-тест `AppIconWidget` (рендер `SvgPicture`, цвет/размер, filled≠outlined) в `test/presentation/widgets/primitives/app_icon_widget_test.dart` — `/widget-test`.
- [x] T008 [US1] Golden-тест `AppIconWidget` (outlined+filled × l/d) в `test/presentation/widgets/primitives/app_icon_widget_golden_test.dart` + baseline `make golden-update FILE=...` — `/golden-test`.
- [x] T009 [P] [US1] `AppSpinnerWidget` в `lib/presentation/widgets/primitives/app_spinner_widget.dart`.
- [x] T010 [US1] Widget-тест `AppSpinnerWidget` в `test/presentation/widgets/primitives/app_spinner_widget_test.dart` — `/widget-test`.
- [x] T011 [US1] Golden-тест `AppSpinnerWidget` (standalone × l/d) в `test/presentation/widgets/primitives/app_spinner_widget_golden_test.dart` + baseline — `/golden-test`.
- [x] T012 [P] [US1] `AppAvatarWidget` (фон `noxAvatarColor`, инициалы/`forum`-fallback) в `lib/presentation/widgets/primitives/app_avatar_widget.dart`.
- [x] T013 [US1] Widget-тест `AppAvatarWidget` (инициалы, fallback-глиф, детерминизм цвета) в `test/presentation/widgets/primitives/app_avatar_widget_test.dart` — `/widget-test`.
- [x] T014 [US1] Golden-тест `AppAvatarWidget` (инициалы+fallback × l/d) в `test/presentation/widgets/primitives/app_avatar_widget_golden_test.dart` + baseline — `/golden-test`.
- [x] T015 [US1] `AppFileGlyphWidget` (тинт `noxFileColor`@14%) в `lib/presentation/widgets/primitives/app_file_glyph_widget.dart` (зависит от T005).
- [x] T016 [US1] Widget-тест `AppFileGlyphWidget` в `test/presentation/widgets/primitives/app_file_glyph_widget_test.dart` — `/widget-test`.
- [x] T017 [US1] Golden-тест `AppFileGlyphWidget` (2–3 типа × l/d) в `test/presentation/widgets/primitives/app_file_glyph_widget_golden_test.dart` + baseline — `/golden-test`.

### Generic state-виджеты

- [x] T018 [US1] `AppProgressWidget` (центрированный `AppSpinnerWidget`) в `lib/presentation/widgets/state/app_progress_widget.dart` (зависит от T009; `FR-010`).
- [x] T019 [US1] Widget-тест `AppProgressWidget` в `test/presentation/widgets/state/app_progress_widget_test.dart` — `/widget-test`.
- [x] T020 [US1] Golden-тест `AppProgressWidget` (l/d) в `test/presentation/widgets/state/app_progress_widget_golden_test.dart` + baseline — `/golden-test`.
- [x] T021 [US1] `AppErrorWidget` (`NoxIcons.error` + message + retry `FilledButton`) в `lib/presentation/widgets/state/app_error_widget.dart` (зависит от T006; `FR-010`).
- [x] T022 [US1] Widget-тест `AppErrorWidget` (message, `onTryAgain`, CTA скрыт без коллбэка) в `test/presentation/widgets/state/app_error_widget_test.dart` — `/widget-test`.
- [x] T023 [US1] Golden-тест `AppErrorWidget` (with-message+retry, icon-only × l/d) в `test/presentation/widgets/state/app_error_widget_golden_test.dart` + baseline — `/golden-test`.
- [x] T024 [P] [US1] `AppEmptyContentWidget` (`Assets.svg.illustrations.*` через flutter_svg) в `lib/presentation/widgets/state/app_empty_content_widget.dart` (`FR-008`, `FR-010`).
- [x] T025 [US1] Widget-тест `AppEmptyContentWidget` (рендер `SvgPicture`, title/message) в `test/presentation/widgets/state/app_empty_content_widget_test.dart` — `/widget-test`.
- [x] T026 [US1] Golden-тест `AppEmptyContentWidget` (empty-chats, empty-messages × l/d) в `test/presentation/widgets/state/app_empty_content_widget_golden_test.dart` + baseline — `/golden-test`.

### Тема stock-виджетов

- [x] T027 [P] [US1] `lib/design/theme/nox_component_themes.dart` — per-component M3 sub-themes (`inputDecoration`/`filledButton`/`textButton`/`iconButton`/`segmentedButton`/`switch`/`radio`/`listTile`/`progressIndicator`/`dialog`/`bottomSheet`/`card`/`snackBar`/`appBar`) из референс `nox_theme.dart` (R5, `FR-009`). `Switch`/`Radio` — M3-дефолт с NOX-ролями; `LinearProgressIndicator` — `primary`/`surfaceVariant`.
- [x] T028 [US1] Подключить sub-themes в `lib/design/theme/app_theme.dart` (`AppTheme._build` → `ThemeData(...)`).
- [x] T029 [US1] Сводный theme-showcase golden `test/design/theme/theme_showcase_golden_test.dart` (FilledButton/TextButton/IconButton/TextField/SegmentedButton/SwitchListTile/RadioListTile/LinearProgressIndicator/AlertDialog/SnackBar/bottom sheet/Card × l/d) + baseline — `/golden-test` (`SC-006`).

**Checkpoint**: US1 функциональна и тестируема независимо — тема + примитивы + состояния. MVP готов.

---

## Phase 4: User Story 2 — Чат/сообщения: composite-виджеты (Priority: P2)

**Goal**: строка чата с unread-бейджем, пузырь сообщения (own/other/статусы/файл), файл-чип, композер, search-бар, segmented.

**Independent Test**: отрендерить список `AppChatItemWidget` + тред `AppMessageBubbleWidget` (варианты) + `AppComposerWidget` + `AppSearchBarWidget`; goldens/widget-тесты проходят.

**Depends on**: US1 (примитивы `AppIconWidget`/`AppAvatarWidget`, `FileType`/`noxFileIcon`).

- [x] T030 [P] [US2] `AppSearchBarWidget` (brand-teal `NoxBrand.teal` иконка, `surfaceContainerHigh`, stadium, `NoxElevation.level2`) в `lib/presentation/widgets/chat/app_search_bar_widget.dart`.
- [x] T031 [US2] Widget-тест `AppSearchBarWidget` (hint vs value, `onTap`) в `test/presentation/widgets/chat/app_search_bar_widget_test.dart` — `/widget-test`.
- [x] T032 [US2] Golden-тест `AppSearchBarWidget` (hint+value × l/d) в `test/presentation/widgets/chat/app_search_bar_widget_golden_test.dart` + baseline — `/golden-test`.
- [x] T033 [P] [US2] `AppChatItemWidget` (avatar-ring + unread-бейдж, cap `99+`, скрыт при 0) в `lib/presentation/widgets/chat/app_chat_item_widget.dart` (использует `AppAvatarWidget`).
- [x] T034 [US2] Widget-тест `AppChatItemWidget` (badge 0/5/120, `onTap`, unread-акцент) в `test/presentation/widgets/chat/app_chat_item_widget_test.dart` — `/widget-test`.
- [x] T035 [US2] Golden-тест `AppChatItemWidget` (unread=0/5/120 × l/d) в `test/presentation/widgets/chat/app_chat_item_widget_golden_test.dart` + baseline — `/golden-test`.
- [x] T036 [P] [US2] `AppFileChipWidget` (standalone/inBubble/removable) в `lib/presentation/widgets/chat/app_file_chip_widget.dart` (использует `FileType`/`AppIconWidget`).
- [x] T037 [US2] Widget-тест `AppFileChipWidget` (ellipsis, `onRemove`, тинт inBubble) в `test/presentation/widgets/chat/app_file_chip_widget_test.dart` — `/widget-test`.
- [x] T038 [US2] Golden-тест `AppFileChipWidget` (standalone/inBubble/removable × l/d) в `test/presentation/widgets/chat/app_file_chip_widget_golden_test.dart` + baseline — `/golden-test`.
- [x] T039 [US2] `AppMessageBubbleWidget` + `MessageStatus` enum (`NoxRadius.bubble(isOwn:)`, статус `NoxIcons.schedule/check/error`, max-width 80%, опц. файл-чип) в `lib/presentation/widgets/chat/app_message_bubble_widget.dart` (использует `AppIconWidget`; встраивает `AppFileChipWidget` — после T036).
- [x] T040 [US2] Widget-тест `AppMessageBubbleWidget` (own/other clip+заливка, статус-иконка, файл-чип, max-width) в `test/presentation/widgets/chat/app_message_bubble_widget_test.dart` — `/widget-test`.
- [x] T041 [US2] Golden-тест `AppMessageBubbleWidget` (own+sent, other, own+file, error × l/d) в `test/presentation/widgets/chat/app_message_bubble_widget_golden_test.dart` + baseline — `/golden-test`.
- [x] T042 [P] [US2] `AppComposerWidget` (attach/text/send active-disabled, опц. attachment) в `lib/presentation/widgets/chat/app_composer_widget.dart` (использует `AppIconWidget`).
- [x] T043 [US2] Widget-тест `AppComposerWidget` (send disabled при пусто, `onSend`/`onAttach`, attachment) в `test/presentation/widgets/chat/app_composer_widget_test.dart` — `/widget-test`.
- [x] T044 [US2] Golden-тест `AppComposerWidget` (empty/with-text/with-attachment × l/d) в `test/presentation/widgets/chat/app_composer_widget_golden_test.dart` + baseline — `/golden-test`.
- [x] T045 [P] [US2] `AppSegmentedWidget<T>` (обёртка над `SegmentedButton`, стилизуется темой) в `lib/presentation/widgets/chat/app_segmented_widget.dart`.
- [x] T046 [US2] Widget-тест `AppSegmentedWidget` (`onChanged`, выбранный сегмент) в `test/presentation/widgets/chat/app_segmented_widget_test.dart` — `/widget-test`.
- [x] T047 [US2] Golden-тест `AppSegmentedWidget` (selected A/B × l/d) в `test/presentation/widgets/chat/app_segmented_widget_golden_test.dart` + baseline — `/golden-test`.

**Checkpoint**: US1 + US2 работают независимо — поверхность чата собирается из кита.

---

## Phase 5: User Story 3 — Оболочка и обратная связь (Priority: P2)

**Goal**: нижний бар + docked `+` FAB, splash-hairline, wordmark, snackbar/banner-хелперы.

**Independent Test**: `Scaffold` с `AppBottomBarWidget` + `AppCreateFabWidget` (centerDocked) и `AppSplashHairlineWidget`/`AppWordmarkWidget`; вызвать feedback-хелперы; goldens/widget-тесты проходят.

**Depends on**: US1 (`AppIconWidget`).

- [x] T048 [P] [US3] `AppSplashHairlineWidget` (`PreferredSizeWidget`, градиент `NoxBrand.teal→lime→gold→coral→red`) в `lib/presentation/widgets/shell/app_splash_hairline_widget.dart` (`FR-006`).
- [x] T049 [US3] Widget-тест `AppSplashHairlineWidget` (`preferredSize`, градиент) в `test/presentation/widgets/shell/app_splash_hairline_widget_test.dart` — `/widget-test`.
- [x] T050 [US3] Golden-тест `AppSplashHairlineWidget` (l/d) в `test/presentation/widgets/shell/app_splash_hairline_widget_golden_test.dart` + baseline — `/golden-test`.
- [x] T051 [P] [US3] `AppWordmarkWidget` (`'NOX'` Bold 700 +0.12em через `textTheme`) в `lib/presentation/widgets/shell/app_wordmark_widget.dart`.
- [x] T052 [US3] Widget-тест `AppWordmarkWidget` (текст/вес/спейсинг) в `test/presentation/widgets/shell/app_wordmark_widget_test.dart` — `/widget-test`.
- [x] T053 [US3] Golden-тест `AppWordmarkWidget` (l/d) в `test/presentation/widgets/shell/app_wordmark_widget_golden_test.dart` + baseline — `/golden-test`.
- [x] T054 [US3] `AppBottomBarWidget` + `AppTab` enum (`BottomAppBar` + `CircularNotchedRectangle`, filled-иконки активной вкладки) в `lib/presentation/widgets/shell/app_bottom_bar_widget.dart` (использует `AppIconWidget`).
- [x] T055 [US3] Widget-тест `AppBottomBarWidget` (`onSelect`, filled у активной, notch-gap) в `test/presentation/widgets/shell/app_bottom_bar_widget_test.dart` — `/widget-test`.
- [x] T056 [US3] Golden-тест `AppBottomBarWidget` (active=chats/settings × l/d) в `test/presentation/widgets/shell/app_bottom_bar_widget_golden_test.dart` + baseline — `/golden-test`.
- [x] T057 [P] [US3] `AppCreateFabWidget` (`primaryContainer`, `NoxElevation.level3`, `NoxIcons.add`) в `lib/presentation/widgets/shell/app_create_fab_widget.dart` (использует `AppIconWidget`).
- [x] T058 [US3] Widget-тест `AppCreateFabWidget` (`onPressed`, иконка add) в `test/presentation/widgets/shell/app_create_fab_widget_test.dart` — `/widget-test`.
- [x] T059 [US3] Golden-тест `AppCreateFabWidget` (l/d) в `test/presentation/widgets/shell/app_create_fab_widget_golden_test.dart` + baseline — `/golden-test`.
- [x] T060 [US3] Feedback-хелперы `showAppSnackBar` (neutral/error) + `showAppBanner` (offline) в `lib/presentation/helpers/app_feedback_helper.dart` (R9, `FR-011`).
- [x] T061 [US3] Widget-тест хелперов (`SnackBar` neutral/error, `MaterialBanner`, `onAction`) в `test/presentation/helpers/app_feedback_helper_test.dart` — `/widget-test`.

**Checkpoint**: US1 + US2 + US3 — оболочка и каналы обратной связи готовы.

---

## Phase 6: User Story 4 — Лаунчер + галерея кита (Priority: P3)

**Goal**: продуктовый стартовый экран — лаунчер `HomePage` с кнопкой «Open UI Kit», открывающей каталог `UiKitPage` со всеми виджетами (light+dark, переключатель темы).

**Independent Test**: `fvm flutter run` → на старте лаунчер → тап «Open UI Kit» → каталог; `AppThemeToggle` переключает тему (`quickstart §3`).

**Depends on**: US1–US3 (все виджеты).

- [x] T062 [US4] `lib/presentation/pages/ui_kit_page/ui_kit_page.dart` — каталог секций Primitives/Chat/State/Feedback&stock со всеми виджетами + `route()`.
- [x] T063 [US4] `lib/presentation/pages/home_page/home_page.dart` — лаунчер (brand-hero + кнопка «Open UI Kit» → `Navigator.push(UiKitPage.route())`); `AppRoot.home` → `HomePage`.
- [x] T064 [US4] `lib/presentation/app/widgets/app_theme_toggle.dart` — общий переключатель темы (`AppRootBloc.SetTheme`), используемый обоими экранами.
- [x] T065 [US4] Widget-тесты `home_page_test` (навигация + тоггл) и `ui_kit_page_test` (секции + тоггл) — `/widget-test`.

**Checkpoint**: все четыре user story функциональны независимо.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: финальная верификация и устранение дрейфа документации.

- [x] T066 Сгенерировать/обновить все goldens локально на M1 (`make golden-update`) и убедиться `make golden-verify` зелёный; застейджить `goldens/*.png` как фикстуры (`quickstart §2`, `SC-001`, `FR-005` — light+dark на каждый виджет).
- [x] T067 [P] Проверка токен-дисциплины: `grep -REn "Color\(0x|EdgeInsets\.|TextStyle\(" lib/presentation/widgets` без совпадений (brand-overrides — исключение); устранить найденное (`SC-003`, `FR-003`, `quickstart §4`).
- [x] T068 [P] Сверка покрытия экранов: подтвердить маппинг «экран→виджет» из `quickstart §5` — net-new ad-hoc виджеты не требуются (`SC-002`).
- [x] T069 Устранить дрейф документации в том же change-set: блюпринт `docs/blueprints/mobile/05 §1` (FUTURE-директория `widgets/` реализована), заметка `.claude/commands/widget-test.md` («no App*Widget yet» — устарела), и подтвердить исправление `FR-007` (font→SVG) (Принцип II/III).
- [x] T070 [P] Доступность (`FR-016`): добавить в widget-тесты интерактивных виджетов (remove-`×` T037, табы T055, FAB T058, composer send/attach T043, search T031) assert'ы tap-таргета ≥48×48; добавить widget-тест устойчивости раскладки при `textScaler=2.0` (нет overflow) для composer/chat-item/bubble; и assert семантики/`tooltip` у icon-only действий (remove-`×`, send/attach, FAB, search, табы) — присутствует `Semantics`-метка или `tooltip` (FR-016 (c)).
- [x] T071 [P] Платформенная нейтральность (`FR-017`): `grep -REn "dart:io|Platform\.|defaultTargetPlatform|kIsWeb" lib/presentation/widgets` без совпадений (leaf-виджеты платформенно-нейтральны).
- [x] T072 [P] BLoC-/DI-нейтральность кита (`FR-002`): `grep -REn "getIt|BlocProvider|BlocBuilder|Repository|configureDependencies" lib/presentation/widgets` без совпадений (переиспользуемые виджеты — без собственного BLoC, без DI/репозиториев).
- [x] T073 Сверка галереи с референсом (`SC-005`): пройтись по каждому виджету в dev-галерее (light/dark) и сверить с `docs/design/system/nox-handoff-2/flutter/widgets/preview.html`; зафиксировать/устранить расхождения.
- [x] T074 Финальный гейт: `make gate` (`generate → format -l 140 → analyze 0 ошибок → test --exclude-tags golden`) зелёный (`SC-004`, `FR-018`).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: без зависимостей.
- **Foundational (Phase 2)**: после Setup; **блокирует все user stories** (`pump_app`, токен-/строко-расширения).
- **US1 (Phase 3)**: после Foundational. MVP.
- **US2 (Phase 4)**: после US1 (примитивы `AppIconWidget`/`AppAvatarWidget`, `FileType`/`noxFileIcon`).
- **US3 (Phase 5)**: после US1 (`AppIconWidget`). Независима от US2.
- **US4 (Phase 6)**: после US1–US3 (галерея рендерит все виджеты).
- **Polish (Phase 7)**: после нужных stories.

### Within Each User Story

- Реализация виджета → widget-тест → golden-тест (baseline на M1).
- Внутристори-зависимости: `AppProgressWidget`←`AppSpinnerWidget`; `AppErrorWidget`←`AppIconWidget`; `AppFileGlyphWidget`←`FileType`; `AppMessageBubbleWidget` встраивает `AppFileChipWidget`; `app_theme` wiring ← `nox_component_themes`.

### Parallel Opportunities

- Foundational T002/T003/T004 — параллельно (разные файлы).
- US1: T005/T006/T009/T012 (разные примитивы) — параллельно; T024 (empty-state) — параллельно; T027 (тема) — независим от примитивов.
- US2: T030/T033/T036/T042/T045 — параллельно (T039 bubble — после T036).
- US3: T048/T051/T057 — параллельно (T054 bar, T060 helpers — независимы по файлам).
- US2 и US3 целиком можно вести параллельно (обе зависят только от US1).
- Polish T067/T068/T070/T071/T072 — параллельно (grep/assert-проверки); T073 — сверка галереи; T074 — гейт последним.

---

## Parallel Example: User Story 1 (после Foundational)

```bash
# Примитивы — разные файлы, параллельно:
Task: "AppIconWidget в lib/presentation/widgets/primitives/app_icon_widget.dart"
Task: "AppSpinnerWidget в lib/presentation/widgets/primitives/app_spinner_widget.dart"
Task: "AppAvatarWidget в lib/presentation/widgets/primitives/app_avatar_widget.dart"
Task: "FileType + maps в lib/presentation/widgets/primitives/file_type.dart"
# Тема параллельно примитивам:
Task: "nox_component_themes.dart в lib/design/theme/nox_component_themes.dart"
```

---

## Implementation Strategy

### MVP First (US1)

1. Phase 1 Setup → 2. Phase 2 Foundational (КРИТИЧНО) → 3. Phase 3 US1 → 4. **STOP & VALIDATE**: тема + примитивы + state-виджеты независимо (`quickstart §1–§2`) → 5. демо.

### Incremental Delivery

1. Setup + Foundational → основа.
2. US1 → проверить → MVP (фундамент + тема).
3. US2 → проверить → поверхность чата.
4. US3 → проверить → оболочка + обратная связь.
5. US4 → проверить → dev-галерея для ручного ревью.
6. Polish → goldens-baselines, токен-дисциплина, дрейф-доков, финальный гейт.

### Parallel Team Strategy

После US1: разработчик A — US2 (chat), разработчик B — US3 (shell/feedback); US4 — после слияния обоих.

---

## Notes

- Тесты **не** TDD-first: golden-baseline требует отрендеренного виджета; widget/golden-тесты идут сразу после реализации виджета (skill-driven `/widget-test`, `/golden-test`).
- Golden-тесты — `@Tags(['golden'])`, локальные (M1/macOS), исключены из CI и `make test`; baselines (`goldens/*.png`) — коммитятся как фикстуры; перед коммитом — `make golden-verify` (CI их не проверяет).
- Виджетам кита DI/моки не нужны (чистые виджеты без `getIt`); `make generate` нужен лишь для `assets.gen.dart`.
- Новых рантайм-зависимостей нет (`material_symbols_icons` не добавляется).
- Коммиты — только с явного подтверждения владельца (репо-правило); работа на ветке `003-ui-kit-widgets`.
- `[P]` = разные файлы без зависимостей; `[USx]` — трассировка к user story.
