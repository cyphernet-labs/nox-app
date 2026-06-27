---
description: "Task list — Chats list design parity + golden coverage"
---

# Tasks: Chats list — сверка с дизайном и golden-покрытие (mobile + desktop)

**Input**: Design documents from `specs/011-chats-design-parity/`

**Prerequisites**: plan.md, spec.md, research.md (R1–R8), data-model.md, contracts/{account-avatar,navigation,golden-coverage}.md, quickstart.md

**Tests**: ВКЛЮЧЕНЫ — фича явно требует golden-покрытие (US4 — ядро задачи), плюс unit-тест правила инициалов и widget-тест навигации (см. contracts/).

**Organization**: задачи сгруппированы по user story для независимой реализации и проверки.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: можно выполнять параллельно (разные файлы, нет зависимостей).
- **[Story]**: US1/US2/US3/US4.
- Каждая задача указывает точный путь к файлу.

## ⚠️ Общие ограничения по файлам (важно для параллельности)

- **`lib/presentation/pages/chats_list_page/chats_list_page.dart` редактируют И US1 (`_mobile`), И US2 (`_desktop`)** → US1 и US2 НЕ параллельны на уровне файла; делать последовательно (US1 → US2), каждая ветка независимо тестируема.
- **`lib/presentation/widgets/shell/app_navigation_rail_widget.dart` трогают US2 (конформность rail) и US3 (trailing-аватар)** → US3-аватар после US2.
- **`test/.../chats_list_page_golden_test.dart`** — один файл для page-mobile и page-desktop кейсов → задачи по нему последовательны.

---

## Phase 1: Setup (Shared)

**Purpose**: подготовить источник истины (макеты) и зафиксировать зелёную стартовую точку.

- [ ] T001 Авторизовать claude_design MCP (`/design-login`) и импортировать оба макета проекта `d9e022e3-07fb-4fae-9147-226210933448`: `NOX - Mobile.html` и `NOX - Desktop.html` — как пиксельный источник истины (см. quickstart.md §1).
- [ ] T002 Прогнать стартовый `make gate` и подтвердить зелёное состояние до правок (фиксация baseline качества).

---

## Phase 2: Foundational (Audit — blocking для US1/US2)

**Purpose**: получить конкретные списки расхождений по каждой вёрстке против импортированных макетов. Блокирует правки US1/US2 (нельзя чинить, не зная дельт). US3 от этой фазы НЕ зависит.

**⚠️ CRITICAL**: правки конформности (US1/US2) не начинать до завершения соответствующего аудита.

- [ ] T003 [P] Аудит mobile `_narrow` `ChatsListPage` против `NOX - Mobile.html` (light+dark): сверить токен-к-токену отступы/типографику/цвета/brand-hairline/тень поля `Search`/бейдж/время/empty-state; зафиксировать список дельт в `specs/011-chats-design-parity/research.md` (раздел «Audit — mobile»). **GATE (A1): T005 не начинать без зафиксированного конкретного delta-list.**
- [ ] T004 [P] Аудит desktop `_wide` `ChatsListPage` + shell-чром против `NOX - Desktop.html` (light+dark): window-titlebar `NOX · Chats`, rail, pane-заголовок `Chats`, no-selection empty-state `Select a chat`, inset-пилюля выбранной строки; зафиксировать дельты в `research.md` (раздел «Audit — desktop»). **GATE (A1): T007 не начинать без зафиксированного конкретного delta-list.**

**Checkpoint**: дельты по обеим вёрсткам известны — конформность можно реализовывать.

---

## Phase 3: User Story 1 — Mobile conformance (Priority: P1) 🎯 MVP

**Goal**: узкая вёрстка `ChatsListPage` пиксельно совпадает с `NOX - Mobile.html` в light и dark.

**Independent Test**: запустить на узкой поверхности (360–420dp), сверить состояния (filled/empty/loading/offline/inline-error/search/search-empty) с мобильным макетом в обеих темах.

- [ ] T005 [US1] Применить дельты аудита (T003) к `_mobile`/`_searchField`/`_banners`/`_list` в `lib/presentation/pages/chats_list_page/chats_list_page.dart` (+ при необходимости `lib/presentation/widgets/chat/app_chat_item_widget.dart`, `lib/presentation/widgets/chat/app_search_field_widget.dart`, `lib/presentation/widgets/shell/app_splash_hairline_widget.dart`) — только дизайн-токены, без хардкода.
- [ ] T006 [US1] Обновить mobile-группу в `test/presentation/pages/chats_list_page/chats_list_page_test.dart` под изменённое дерево (селекторы wordmark/search/rows/тап→thread остаются зелёными).

**Checkpoint**: mobile-вёрстка соответствует дизайну и функционально зелёная.

---

## Phase 4: User Story 2 — Desktop conformance (Priority: P1)

**Goal**: широкая вёрстка (list-detail + shell-чром) пиксельно совпадает с `NOX - Desktop.html` в light и dark.

**Independent Test**: запустить на широкой поверхности (≥1280dp), сверить состояния (filled/selected/no-selection/loading/offline/search/search-empty) с десктопным макетом в обеих темах.

- [ ] T007 [US2] Применить дельты аудита (T004) к `_desktop`/`_paneHeader`/`_threadPane`/`_list` (desktop-ветка подсветки) в `lib/presentation/pages/chats_list_page/chats_list_page.dart` (+ при необходимости `lib/presentation/widgets/shell/app_window_titlebar_widget.dart`, `lib/presentation/widgets/shell/app_navigation_rail_widget.dart`, `lib/presentation/widgets/shell/app_list_detail_widget.dart`) — только токены.
- [ ] T008 [US2] Обновить desktop-группу в `test/presentation/pages/chats_list_page/chats_list_page_test.dart` под изменённое дерево (list-detail, no-selection placeholder, select→thread-pane без push остаются зелёными).

**Checkpoint**: desktop-вёрстка соответствует дизайну и функционально зелёная (US1+US2 независимо проверяемы).

---

## Phase 5: User Story 3 — Account avatar в desktop-rail (Priority: P2)

**Goal**: внизу desktop-rail — аккаунт-аватар (инициалы по account-правилу, визуал как у чатов); тап → `Settings` + секция `Account`.

**Independent Test**: на широкой поверхности аватар внизу rail показывает корректные инициалы (`User7421`→`U`, `john.doe`→`JD`); тап переключает на `Settings`/`Account`; на узкой поверхности аватара нет.

> Зависит от Phase 1 (Setup). НЕ зависит от аудита (Phase 2). T012 (rail) делать ПОСЛЕ US2 T007 (общий файл `app_navigation_rail_widget.dart`).

- [ ] T009 [US3] Написать падающий unit-тест `test/design/theme/nox_account_initials_test.dart` по таблице из `contracts/account-avatar.md` (`User7421`→`U`, `john.doe`→`JD`, `john_doe_smith`→`JS`, `a-b-c`→`AC`, `Alice`→`A`, `nox.core.team`→`NT`, `` /`...`→`null`). Без `@Tags`.
- [ ] T010 [US3] Реализовать `noxAccountInitials(String label)` в `lib/design/theme/nox_brand.dart` (split по `RegExp(r'[\s._-]+')`, первый+последний токен, один токен → 1 буква) — unit-тест T009 зелёный.
- [ ] T011 [P] [US3] Добавить опциональный `final String? initials;` в `lib/presentation/widgets/primitives/app_avatar_widget.dart` (если задан — рисуем его, иначе текущий `noxInitials(name)`; фон всегда `noxAvatarColor(name)`) — обратносовместимо, аватары чатов не меняются.
- [ ] T012 [US3] Добавить trailing аккаунт-аватар в `lib/presentation/widgets/shell/app_navigation_rail_widget.dart`: `NavigationRail.trailing` = `Expanded`+`Align.bottomCenter` вокруг кликабельного `AppAvatarWidget(name: accountLabel, initials: noxAccountInitials(accountLabel), size: <token>)`, tooltip `Account`; новые параметры `String? accountLabel` + `VoidCallback onAccount`. (depends T010, T011; ПОСЛЕ T007)
- [ ] T013 [US3] Прокинуть данные/действие в `lib/presentation/widgets/shell/tab_bar_shell_widget.dart`: one-shot `sessionRepository.readSession()`→`_accountLabel` (fallback `User7421`); передать в rail; `onAccount` → `setState(_active = AppTab.settings)` + `_settingsJumpToAccount.value++`; добавить `ValueNotifier<int> _settingsJumpToAccount` (+ dispose). (depends T012)
- [ ] T014 [US3] Принять сигнал в `lib/presentation/pages/settings_root_page/settings_root_page.dart`: новый `ValueListenable<int>? jumpToAccount` (по образцу `scrollToTop`); listener по бампу → `setState(_selected = _Section.account)`; подключить в `initState`/`dispose`. Прокинуть из `TabBarShell` (T013). **(U1a) Сигнал desktop-only по эффекту**: аватар существует лишь в rail, поэтому `jumpToAccount` бампится только на широком окне; на узком (mobile) `SettingsRootPage` корректно игнорирует его (плоский список без `_selected`). (depends T013)
- [ ] T015 [US3] Widget-тест навигации `test/presentation/widgets/shell/tab_bar_shell_account_avatar_test.dart`: на широкой поверхности тап аватара в смонтированном `TabBarShell` → активна `Settings` И видна секция `Account` (`contracts/navigation.md`). **(G2) Дополнительно**: на узкой поверхности (bottom-bar) ассертить отсутствие аккаунт-аватара (`AppAvatarWidget` нет в rail/нижней панели). Без `@Tags`.
- [ ] T016 [P] [US3] Drift-fix `docs/design/system/nox-desktop-screens/screens/01-chats.md`: добавить trailing account-аватар в анатомию rail + поведение перехода в `Settings`/`Account` (Принцип II).

**Checkpoint**: аватар работает; US1+US2+US3 независимо функциональны.

---

## Phase 6: User Story 4 — Golden coverage (Priority: P2)

**Goal**: весь функционал экрана зафиксирован golden-baseline в двух категориях (page-mobile + page-desktop) + widget-golden rail с аватаром.

**Independent Test**: `make golden-verify` зелёный; намеренная визуальная регрессия ловится; `make gate` остаётся зелёным.

> Зависит от финального визуала US1+US2+US3 (goldens снимаются с уже приведённого к дизайну экрана). Гранулярность кейсов — по `contracts/golden-coverage.md`.

- [ ] T017 [US4] Создать `test/presentation/pages/chats_list_page/chats_list_page_golden_test.dart` (`@Tags(['golden'])`) с page-mobile кейсами `goldenTest`: `chats_list_page_filled`, `_empty`, `_loading` (settle:false), `_offline`, `_error`, `_search_empty` — состояния через `ChatsListScenario` + ввод в `AppSearchFieldWidget`, под `configureDependencies(Environment.test)`.
- [ ] T018 [US4] В том же файле добавить page-desktop кейсы `goldenTestDesktop`: `chats_list_page` (no-selection), `_selected`, `_empty`, `_search_empty`. **(U1b) Решение зафиксировано**: рендерить `_wide` через смонтированный `TabBarShell` (широкая поверхность), чтобы в desktop-golden попали rail + window-titlebar + аккаунт-аватар (полный десктопный вид экрана), а не изолированная страница с `forceWide`. Зафиксировать это в комментарии теста.
- [ ] T019 [P] [US4] Создать/обновить `test/presentation/widgets/shell/app_navigation_rail_widget_golden_test.dart` (`@Tags(['golden'])`): widget-golden rail c аккаунт-аватаром (`Chats` активна), light+dark.
- [ ] T020 [P] [US4] Удалить осиротевшую папку `test/presentation/pages/chats_list_page/failures/` (артефакт прежнего упавшего golden).
- [ ] T021 [US4] Сгенерировать baseline (`make golden-update FILE=…` для новых golden-файлов) и проверить `make golden-verify` — зелёный; закоммитить `goldens/*.png`. **(G1) Scope включает перегенерацию ВСЕХ затронутых СУЩЕСТВУЮЩИХ widget-goldens**, если US1/US2 изменили их виджеты: `test/presentation/widgets/chat/app_chat_item_widget_golden_test.dart` и `app_search_field_widget` (если есть golden), а не только новые файлы. (depends T017, T018, T019)

**Checkpoint**: экран полностью golden-locked в обеих категориях.

---

## Phase 7: Polish & Cross-Cutting

**Purpose**: финальная сверка, гейты, согласование корпусов.

- [ ] T022 [P] Формат изменённых файлов: `fvm dart format -l 140 <changed lib/ + test/ paths>`.
- [ ] T023 Прогнать `make gate` (generate → format → analyze → test, goldens исключены) — зелёный, `flutter analyze` без ошибок.
- [ ] T024 Прогнать `make golden-verify` — зелёный (включая перегенерированные существующие widget-goldens из T021/G1); подтвердить SC-005 (намеренная дельта отступа/цвета ловится тестом — ручная проверка/revert).
- [ ] T025 [P] Сверить мобильный корпус `docs/design/system/nox-mobile-screens/screens/5-1-chats.md` с финальным состоянием; при расхождении — привести корпус (Принцип II). Desktop-корпус уже обновлён в T016.
- [ ] T026 Пройти `quickstart.md` Definition of Done: обе вёрстки ↔ макеты (SC-001/002), аватар (SC-003/004), goldens (SC-005/006), multi-platform parity (`_narrow`↔mobile, `_wide`↔desktop).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: без зависимостей.
- **Foundational/Audit (Phase 2)**: после Setup; блокирует US1/US2 (НЕ US3).
- **US1 (Phase 3)**: после T003. MVP.
- **US2 (Phase 4)**: после T004. Делить файл `chats_list_page.dart` с US1 → выполнять ПОСЛЕ US1.
- **US3 (Phase 5)**: после Setup; T012 ПОСЛЕ US2 T007 (общий rail-файл).
- **US4 (Phase 6)**: после US1+US2+US3 (финальный визуал).
- **Polish (Phase 7)**: после US4.

### User Story Dependencies

- **US1 (P1)**: независимо тестируема; общий файл с US2 → секвенс.
- **US2 (P1)**: независимо тестируема; после US1 (общий файл).
- **US3 (P2)**: независимо тестируема; rail-задача после US2.
- **US4 (P2)**: зависит от завершённости US1–US3 (goldens с финального визуала).

### Within US3 (порядок)

T009 (failing test) → T010 (impl) → T011 (avatar override, [P]) → T012 (rail) → T013 (shell) → T014 (settings signal) → T015 (widget test) / T016 (corpus, [P]).

### Parallel Opportunities

- **Phase 2**: T003 ∥ T004 (разные вёрстки, read-only).
- **US3**: T011 ∥ (после T010); T016 ∥ T015.
- **US4**: T019 ∥ T020 (разные файлы); T017→T018 последовательны (один файл).
- **Polish**: T022 ∥ T025.

---

## Parallel Example: Phase 2 (Audit)

```bash
# Аудит обеих вёрсток одновременно (read-only, разные макеты):
Task: "T003 mobile audit ChatsListPage vs NOX - Mobile.html"
Task: "T004 desktop audit ChatsListPage + shell vs NOX - Desktop.html"
```

## Parallel Example: User Story 4 (Golden)

```bash
# Параллельно (разные файлы):
Task: "T019 rail widget golden in test/presentation/widgets/shell/app_navigation_rail_widget_golden_test.dart"
Task: "T020 remove orphaned test/presentation/pages/chats_list_page/failures/"
```

---

## Implementation Strategy

### MVP First

1. Setup (T001–T002).
2. Audit mobile (T003).
3. US1 (T005–T006) → **STOP & VALIDATE**: mobile-вёрстка ↔ `NOX - Mobile.html`. Это минимальный полезный инкремент.

### Incremental Delivery

1. Setup + Audit → база готова.
2. US1 (mobile conformance) → проверить → демо.
3. US2 (desktop conformance) → проверить → демо.
4. US3 (account avatar) → проверить → демо.
5. US4 (golden lock) → `make golden-verify` зелёный → демо.
6. Polish → полный гейт.

### Notes

- [P] = разные файлы, нет зависимостей.
- golden-файлы — `*_golden_test.dart` + ОБЯЗАТЕЛЬНО `@Tags(['golden'])`; обычные — без тега.
- Только дизайн-токены (Принцип IV); сырые `Color` — лишь внутри `lib/design/theme/`.
- Коммитить после логических групп; перед завершением — `make gate` + `make golden-verify` (CI на паузе, локальный гейт обязателен).
- Multi-platform parity: каждая правка проверяется и в `_narrow`, и в `_wide`.
