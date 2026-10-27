# Tasks: Экраны этапа M3 — Шелл, корень настроек, список чатов

**Input**: Design documents from `specs/006-shell-settings-chats/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: ВКЛЮЧЕНЫ — спека требует явно (FR-007: каждый экран покрыт widget + golden; DoD roadmap) + `bloc_test` на `ChatsListBloc`/`SettingsRootBloc` + gallery-тест + unit-тест relative-time форматтера. Golden-бейзлайн рендерится после готового виджета (не строгий TDD-first).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: можно выполнять параллельно (разные файлы, нет незавершённых зависимостей)
- **[Story]**: US1–US3 из spec.md (фазы Setup/Foundational/Polish — без метки)
- Каждый таск содержит точный путь к файлу

## Path Conventions

Один пакет `nox_app`: код в `lib/`, тесты deep-mirror в `test/`. M3 — первый этап с **domain+data** слоем (chats-вертикаль). Страницы — `lib/presentation/pages/<page>_page/` (BLoC — в `bloc/` рядом); шелл/контейнеры — `lib/presentation/widgets/shell/`. Навигация — `Navigator.push(<Page>.route()/routeDemo())` (роутера нет). Приоритет историй: **US1 (4.1 шелл, P1) → US2 (7.1 настройки, P2) → US3 (5.1 чаты, P3)**.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Базовая готовность; новые зависимости НЕ добавляются.

- [ ] T001 Подтвердить, что новые зависимости не нужны (`qr_flutter` — Фаза 2; QR — fake-stub; relative-time на уже доступном `intl`; debounce — существующий `debounceRestartable()`; `infinite_scroll_pagination` v5 уже в `pubspec`) и снять базовый зелёный `make gate` до изменений (без правок `pubspec.yaml`).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Общие блоки для нескольких историй. ⚠️ Завершить до US1–US3.

- [ ] T002 [P] Добавить всю UI-микрокопию M3 (English) в `lib/general/text_constants.dart`, сгруппировав комментариями по экранам; **переиспользовать** существующие `chats`/`settings`/`searchHint`/`appName`/`noConnection`/`comingSoon`/`actionCancel`/`tooltipBack`/`tooltipCreateChat`/`usernameLabel`/`usernameCharsetError`/`nameTakenError`/`settings{Notifications,Appearance,Language,Terms,About}Title`/`loginIdLabel`. Новые — **7.1** (≈14): `settingsNameEditTooltip` (`Edit`), `idMask` (`••••••••`), `idShowTooltip` (`Show`), `idHideTooltip` (`Hide`), `idCopyTooltip` (`Copy`), `idShowQrTooltip` (`Show QR`), `qrSheetTitle` (`Your ID QR`), `actionClose` (`Close`), `copiedToClipboard` (`Copied to clipboard`), `logoutRow` (`Log out`), `logoutDialogTitle` (`Log out?`), `logoutDialogMessage` (`Your ID and local data will be removed from this device.`); **5.1** (≈4): `chatsEmptyTitle` (`No chats yet`), `chatsEmptyMessage` (`Tap + to create the first one.`), `chatsSearchEmpty` (`No chats found`), `chatsLoadError` (`Could not load chats. Pull to refresh.`); **relative-time** (R6): `timeNow` (`now`), `timeYesterday` (`Yesterday`); **desktop no-selection** (5.1): `chatsNoSelectionTitle` (`Select a chat`), `chatsNoSelectionMessage` (`Choose a conversation on the left, or press + to start a new one.`). См. research.md R11.
- [ ] T003 [P] Добавить 4 темы стоковых компонентов в `lib/design/theme/nox_component_themes.dart` и собрать в `AppTheme._build`: `SearchBarThemeData` (5.1 поле, `surfaceContainerHigh`/`level2`), `MaterialBannerThemeData` (5.1 офлайн/inline-error, `surfaceContainer`/`level3`), `BadgeThemeData(backgroundColor: cs.primary)` (5.1 unread — НЕ стоковый error-red), `NavigationRailThemeData` (4.1 десктоп-rail, selected `primary`). См. research.md R10.
- [ ] T004 [P] Создать `AppListDetailWidget` в `lib/presentation/widgets/shell/app_list_detail_widget.dart`: `Row[ConstrainedBox(width: listPaneWidth), VerticalDivider(1), Expanded(detailPane)]`; highlight выбранной строки `secondaryContainer` (на стороне item), без push; слот no-selection. Контракт — `contracts/widgets.md`. Переиспользуют US2 (desktop 7.1) и US3 (desktop 5.1).
- [ ] T005 [P] Widget+golden тест `AppListDetailWidget` (list-pane + detail-pane, no-selection слот) в `test/presentation/widgets/shell/app_list_detail_widget_*.dart` + бейзлайны (зависит от T004).

**Checkpoint**: общие блоки готовы — истории можно реализовывать.

---

## Phase 3: User Story 1 — Адаптивный шелл (Tab-bar shell, 4.1) (Priority: P1) 🎯 MVP

**Goal**: Скелет приложения: адаптивный шелл (мобайл bottom-bar + center-docked `+` ↔ десктоп rail + leading `+`), `IndexedStack` с сохранением табов, `+` → реальный 6.1 (width-adaptive), системный back, scroll-to-top. Хостит табы (на старте — существующие плейсхолдеры; US2/US3 подменяют реальными).

**Independent Test**: Открыть 4.1 из Галереи (узкое/широкое, light/dark); узкое — `BottomAppBar`+вырез+docked `+`; широкое (≥840) — `NavigationRail`+leading `+`; переключение Chats↔Settings сохраняет состояние; `+` → 6.1 (мобайл fullscreen / десктоп `Dialog`); back: Settings→Chats; re-tap Chats→scroll-top.

- [ ] T006 [US1] Создать `AppNavigationRailWidget` в `lib/presentation/widgets/shell/app_navigation_rail_widget.dart`: `NavigationRail` (две цели — `NoxIcons.forum/forumFill` `Chats`, `settings/settingsFill` `Settings`; selected `primary`) + **leading** `AppCreateFabWidget(onPressed: onCreate)`; параметры `active`/`onSelect`/`onCreate`. Контракт — `contracts/widgets.md` (зависит от T003).
- [ ] T007 [US1] Создать `TabBarShell` в `lib/presentation/widgets/shell/tab_bar_shell_widget.dart`: `StatefulWidget` **без BLoC** — локальный `AppTab _active` (reuse enum) + `setState`; body `IndexedStack(index: _active.index, children: [chatsBody, settingsBody])` с cross-fade `NoxDuration.tabFade`(150мс)+`NoxEasing.standard`; `LayoutBuilder` по `Constants.railBreakpoint`(840): мобайл `Scaffold(bottomNavigationBar: AppBottomBarWidget(active,onSelect), floatingActionButton: AppCreateFabWidget(onPressed:_onCreate), floatingActionButtonLocation: centerDocked)` / десктоп `Scaffold(body: Row[AppNavigationRailWidget(...), VerticalDivider(1), Expanded(body)])`; `_onCreate` → `Navigator.push(CreateChatPage.route())`; `PopScope` back: не-Chats→`chats`, Chats→`SystemNavigator.pop` (`// TODO(backend):` в превью); re-tap Chats→scroll-top (callback к 5.1); **на старте** `chatsBody`/`settingsBody` = существующие `ChatsPlaceholderPage`/`SettingsPlaceholderPage` (US3/US2 подменят); `static Route<void> route()`→`/shell`. Контракт — `contracts/{widgets,navigation}.md` (зависит от T006).
- [ ] T008 [US1] Активировать строку `4.1` (`route: TabBarShell.route`, раздел `Shell`) в `lib/presentation/pages/screens_gallery_page/screens_gallery_page.dart` (+import) и добавить проверку навигации в `test/presentation/pages/screens_gallery_page/screens_gallery_page_test.dart` (зависит от T007).
- [ ] T009 [P] [US1] Widget-тест `TabBarShell` в `test/presentation/widgets/shell/tab_bar_shell_widget_test.dart`: tab-switch сохраняет состояние (`IndexedStack`); ширина <840 → `AppBottomBarWidget`, ≥840 → `AppNavigationRailWidget`; `+` пушит `CreateChatPage`; back Settings→Chats (зависит от T007).
- [ ] T010 [P] [US1] Golden-тест `TabBarShell` (light/dark; мобайл bottom-bar + десктоп rail) в `test/presentation/widgets/shell/tab_bar_shell_widget_golden_test.dart` + бейзлайны (зависит от T007).
- [ ] T011 [P] [US1] Widget+golden тест `AppNavigationRailWidget` (две цели + leading FAB) в `test/presentation/widgets/shell/app_navigation_rail_widget_*.dart` + бейзлайны (зависит от T006).

**Checkpoint**: US1 (MVP) — адаптивный шелл функционален и тестируем независимо (на плейсхолдер-табах).

---

## Phase 4: User Story 2 — Корень настроек (Settings root, 7.1) (Priority: P2)

**Goal**: Таб Settings: identity-card (имя inline-edit + `Your ID` mask/Copy/QR), плоский список разделов → реальные 7.2–7.7, Logout → реальный 1.1 Splash; десктоп — list-detail (menu-pane 340 + detail-pane ≤680, swap без push, no-reveal + inline-QR).

**Independent Test**: Открыть 7.1 (standalone + внутри шелла, узкое/широкое, light/dark); name-edit charset/taken/valid; `Your ID` мобайл `Show/Hide`+`Copy`(snackbar)+`Show QR`(светлая поверхность), десктоп — без reveal + inline-QR; строки → реальные подэкраны; `Log out`→диалог→loading→реальный Splash.

- [ ] T012 [P] [US2] Извлечь body M1-подэкранов в ПУБЛИЧНЫЕ виджеты (без `Scaffold`/`AppBar`) в файлах `lib/presentation/pages/notifications_page/notifications_body.dart` (`NotificationsBody`), `lib/presentation/pages/appearance_page/appearance_body.dart` (`AppearanceBody`), `lib/presentation/pages/language_page/language_body.dart` (`LanguageBody`), `lib/presentation/pages/about_page/about_body.dart` (`AboutBody`), и сделать `_TermsBody` → public `TermsBody` в `lib/presentation/pages/terms_page/terms_page.dart`; рефакторить каждую страницу-мобайл (`*_page.dart`) на `AppDetailScaffoldWidget(body: …Body)` (поведение не меняется). Для desktop detail-pane 7.1 (research.md R8).
- [ ] T013 [P] [US2] Создать `AppSettingsNavRowWidget` в `lib/presentation/widgets/settings/app_settings_nav_row_widget.dart`: `ListTile(title, onTap, color?)` (icon-less; `color` для `Log out` = `ColorScheme.error`). Контракт — `contracts/widgets.md`.
- [ ] T014 [P] [US2] Создать `AppLogoutDialogWidget` в `lib/presentation/widgets/settings/app_logout_dialog_widget.dart`: `AlertDialog`(`logoutDialogTitle`/`logoutDialogMessage`/`logoutRow`·`actionCancel`); `loading` → confirm disabled+`AppSpinnerWidget`, модален. Контракт — `contracts/widgets.md` (зависит от T002).
- [ ] T015 [P] [US2] Создать `AppQrSurfaceWidget` в `lib/presentation/widgets/settings/app_qr_surface_widget.dart`: **fake-QR** (нейтральный детерминированный паттерн) на brand-fixed светлой поверхности `NoxBrand.qrSurface`(#FFFFFF)+`qrInk`(#0C0C0C), quiet-zone, **вне `ColorScheme`** (design-system §9.10); реальное кодирование `// TODO(backend):` (без `qr_flutter`). Контракт — `contracts/widgets.md` (research.md R5).
- [ ] T016 [US2] Создать `AppIdentityCardWidget` в `lib/presentation/widgets/settings/app_identity_card_widget.dart`: filled `Card`; generated avatar (`AppAvatarWidget`); Name-блок (`usernameLabel` + имя + edit-pencil `NoxIcons.edit`; editing → слот `nameEditField`=`AppLabeledFieldWidget(maxLength:32)`); `Your ID`-блок (mask `idMask` + action-row). **Параметризация по раскладке**: `revealable` (мобайл true: `Show/Hide` `NoxIcons.visibility`/`visibilityOff` → raw `AppTextStyleTokens.monoBody` wrap; десктоп false), `showInlineQr` (десктоп true: inline `AppQrSurfaceWidget`); действия `Copy`(`contentCopy`)/`Show QR`(`qrCode`). Контракт — `contracts/widgets.md` (зависит от T015, T002).
- [ ] T017 [US2] Создать `SettingsRootBloc`-трио в `lib/presentation/pages/settings_root_page/bloc/{settings_root_state.dart,settings_root_event.dart,settings_root_bloc.dart}`: **value-state** (как `CreateChatState`: `abstract`+`._()`+getters; поля `initialLoading`/`name`/`draftName`/`editing`/`status`(`SettingsNameStatus`)/`idRevealed`/`logoutPhase`/`outcome`; getters `canSave`/`errorText`/`maskedId`/`rawId`); `Initialize` снимает `initialLoading` после фейк-`Future` (Initial-loading: спиннер в позиции ID, FR-038); `rawId` — зафиксированная мок-константа, `name` default `User7421`; name-edit charset (`[A-Za-z0-9._-]`) + availability `debounceRestartable()` против `OnboardingMockData.takenUsernames` (case-sensitive); logout через `BaseBloc.executeLogic(onError:)` (фейк-`Future`); `// TODO(backend):`. См. data-model.md (зависит от T002).
- [ ] T018 [US2] Создать `SettingsRootPage` в `lib/presentation/pages/settings_root_page/settings_root_page.dart`: `State extends BaseStatePage` + `BlocProvider.value`(`SettingsRootBloc`); **мобайл** — `Scaffold`+`AppBar`(`settings` title, actions `AppThemeToggle`)+`ListView`[`AppIdentityCardWidget(revealable:true)` + `AppSettingsNavRowWidget`×5 (`Notifications`/`Appearance`/`Language`/`Terms`/`About` → `…Page.route()` push) + `Log out` (error) → `AppLogoutDialogWidget`]; **десктоп** — `AppListDetailWidget`(menu-pane 340 = nav-rows + identity; detail-pane ≤680 = выбранный `…Body` без AppBar, swap без push, **по умолчанию = блок идентичности/account**; `AppIdentityCardWidget(revealable:false, showInlineQr:true)`); `Show QR` → bottom sheet (мобайл) / `Dialog` (десктоп) с `AppQrSurfaceWidget`; `Copy` → `showAppSnackBar(copiedToClipboard)`; logout-confirm→loading→`Navigator.…(SplashPage.route())`; `route()`/`routeDemo()`→`/settings`. Контракт — `contracts/{widgets,navigation}.md` (зависит от T016, T017, T013, T014, T012, T004).
- [ ] T019 [US2] Подменить таб Settings в `TabBarShell` (`tab_bar_shell_widget.dart`): `settingsBody` = `SettingsRootPage` (вместо `SettingsPlaceholderPage`) (зависит от T018, T007).
- [ ] T020 [US2] Активировать строку `7.1` (`route: SettingsRootPage.routeDemo`, раздел `Settings`) в `screens_gallery_page.dart` (+import) + проверка навигации в gallery-тесте (зависит от T018).
- [ ] T021 [P] [US2] `bloc_test` `SettingsRootBloc` в `test/presentation/pages/settings_root_page/bloc/settings_root_bloc_test.dart`: name-edit charset/checking/valid/taken (case-sensitive); save; logout-phase (Error/fatal только при `onError`) (зависит от T017).
- [ ] T022 [P] [US2] Widget-тест `SettingsRootPage` в `test/presentation/pages/settings_root_page/settings_root_page_test.dart`: name-edit, `Copy`-snackbar, QR sheet/dialog, строки → реальные подэкраны, `Log out`→`AppLogoutDialogWidget`→пушит `SplashPage`; десктоп list-detail swap без push; десктоп no-reveal (зависит от T018).
- [ ] T023 [P] [US2] Golden-тест `SettingsRootPage` (light/dark; мобайл list + десктоп list-detail; Loaded/Name-editing/QR-overlay/Logout) в `test/presentation/pages/settings_root_page/settings_root_page_golden_test.dart` + бейзлайны (зависит от T018).
- [ ] T024 [P] [US2] Widget+golden тест `AppIdentityCardWidget` (мобайл revealable `Show/Hide` + десктоп no-reveal+inline-QR) в `test/presentation/widgets/settings/app_identity_card_widget_*.dart` + бейзлайны (зависит от T016).
- [ ] T025 [P] [US2] Widget+golden тест `AppQrSurfaceWidget` (brand-fixed #FFFFFF/#0C0C0C **идентичны** light/dark) в `test/presentation/widgets/settings/app_qr_surface_widget_*.dart` + бейзлайны (зависит от T015).
- [ ] T026 [P] [US2] Widget-тесты `AppSettingsNavRowWidget` + `AppLogoutDialogWidget` (loading-состояние) + извлечённых `…Body` (рендер) в `test/presentation/widgets/settings/` и `test/presentation/pages/{notifications,appearance,language,about,terms}_page/` (зависит от T013, T014, T012).

**Checkpoint**: US2 независимо тестируема; реальная композиция строк настроек + Logout→Splash.

---

## Phase 5: User Story 3 — Список чатов (Chats list, 5.1) (Priority: P3)

**Goal**: Таб Chats: network-only мок-вертикаль + список (avatar+name+preview+relative-time+unread-бейдж), поиск, pull-to-refresh, офлайн-баннер; десктоп — list-detail (list-pane 360 + thread-pane = M4-плейсхолдер).

**Independent Test**: Открыть 5.1 (standalone + внутри шелла, узкое/широкое, light/dark); список из мок-репозитория; debug: loading/empty/filled/search-empty/offline/error/fatal; тап по чату → `Chat thread (5.2)` плейсхолдер; десктоп — выбор строки highlight без push, no-selection `Select a chat`.

- [ ] T027 [P] [US3] Создать `ChatModel` в `lib/domain/model/chat/chat_model.dart` (`@freezed`: `id`/`name`/`lastMessagePreview`/`lastMessageAt: DateTime`/`unreadCount` `@Default(0)`) и `GetChatsConfig` в `lib/domain/repository/chat/get_chats_config.dart` (`{page, search}`, `pageSize`/`defaultPage`, `firstPage`/`nextPage` — зеркало `GetItemsConfig`). См. data-model.md.
- [ ] T028 [US3] Создать мок-`GetChatsApi` (`@lazySingleton`) в `lib/data/remote/api/chat/get_chats_api.dart`: синтезирует ~30 мок-`ChatModel` (имена/превью/время/unread детерминированы; ≥1 `unread>99` для cap `99+`, часть `unread=0` без бейджа, достаточно строк для пагинации и поиска) + задержка + `PageMetadata`, фильтрует по `config.search` (зеркало `GetItemsApi`) (зависит от T027).
- [ ] T029 [US3] Создать `ChatRepository` (`lib/domain/repository/chat/chat_repository.dart`) + `ChatRepositoryImpl` (`@LazySingleton(as: ChatRepository, env: [dev, prod, test])`, `lib/data/repository/chat/chat_repository_impl.dart`) → `RepositoryResult<(List<ChatModel>, PageMetadata)>` (зеркало `ItemRepositoryImpl`); `make generate` (DI `*.config.dart`) (зависит от T028).
- [ ] T030 [P] [US3] Добавить `static String relative(DateTime, {DateTime? now})` в `lib/general/formatters/date_formatter.dart` — лестница `timeNow`/`5 min`/`2 h`/`timeYesterday`/`d MMM`/`d MMM y` на `intl` (research.md R6) (зависит от T002).
- [ ] T031 [P] [US3] Создать `AppSearchFieldWidget` (РЕДАКТИРУЕМОЕ) в `lib/presentation/widgets/chat/app_search_field_widget.dart`: `SearchBar`/`TextField` + `controller`/`onChanged`, suffix `NoxIcons.search`, тема `SearchBarThemeData`. (Существующий `AppSearchBarWidget` — display-only.) Контракт — `contracts/widgets.md` (зависит от T003).
- [ ] T032 [US3] Создать `ChatsListBloc`-трио в `lib/presentation/pages/chats_list_page/bloc/{chats_list_state.dart,chats_list_event.dart,chats_list_bloc.dart}`: **sealed** `Initializing/Initialized(pagingState, query, isOffline, selectedChatId, loadingInProgress)/Error` (зеркало `ItemListBloc`); `super(initializing())`; `on<Initialize>`→`Initialized(PagingState())`+`loadChats(reset:true)`; `on<LoadChats>(transformer: sequential())`; `on<SearchChanged>(transformer: debounceRestartable())`→reset+reload; `on<ChatSelected>` (desktop); `on<SetScenario>` (debug — `ChatsListScenario{normal,empty,inlineError,fatal,offline}` детерминированно воспроизводит Empty/Inline-error/Fatal/Offline на стабе; Search-empty — естественно непустым запросом); `getIt<ChatRepository>()`, `executeLogic(onError: emit(error))`, `result.match`, `PagingStateExt.applyPage(keyExtractor:(c)=>c.id)`, re-check `state is Initialized` после `await`. См. data-model.md (зависит от T029).
- [ ] T033 [US3] Создать `ChatsListPage` в `lib/presentation/pages/chats_list_page/chats_list_page.dart`: `State extends BaseStatePage` + `BlocProvider.value`(`ChatsListBloc`); **мобайл** — `Scaffold`+`AppBar`(`AppWordmarkWidget` + `AppSplashHairlineWidget` bottom + `AppThemeToggle`) + `AppSearchFieldWidget` + `PagedListView<String,ChatModel>.separated` в `RefreshIndicator` (item `AppChatItemWidget(name, preview, time: DateFormatter.relative(c.lastMessageAt), unread, onTap)`); `Initializing`→`AppProgressWidget`, empty→`AppEmptyContentWidget(emptyChats, chatsEmptyTitle, chatsEmptyMessage)`, search-empty→`chatsSearchEmpty`, `Error`→`AppErrorWidget(onTryAgain:)`, offline→`showAppBanner(noConnection)`, inline-error→`showAppBanner(chatsLoadError)`; тап→`RoutePlaceholderPage('Chat thread (5.2)')` `// TODO(M4):`; **десктоп** — `AppListDetailWidget`(list-pane 360 = pane-header+`AppSearchFieldWidget`+список; thread-pane: выбор→highlight `secondaryContainer` без push, content = **M4-плейсхолдер**, no-selection→`chatsNoSelectionTitle`/`chatsNoSelectionMessage`); `route()`/`routeDemo()`→`/chats`. Контракт — `contracts/{widgets,navigation}.md` (зависит от T032, T030, T031, T004).
- [ ] T034 [US3] Подменить таб Chats в `TabBarShell` (`tab_bar_shell_widget.dart`): `chatsBody` = `ChatsListPage` (вместо `ChatsPlaceholderPage`) + подключить re-tap-Chats→scroll-top callback (зависит от T033, T007).
- [ ] T035 [US3] Активировать строку `5.1` (`route: ChatsListPage.routeDemo`, раздел `Chats`) в `screens_gallery_page.dart` (+import) + проверка навигации в gallery-тесте (зависит от T033).
- [ ] T036 [P] [US3] `bloc_test` `ChatsListBloc` в `test/presentation/pages/chats_list_page/bloc/chats_list_bloc_test.dart`: `Initializing→Initialized` (paging); `searchChanged` reset+filter; `setOffline`; `Error` только при `onError`; против test-env DI (`ChatRepository` env `test`) (зависит от T032).
- [ ] T037 [P] [US3] Widget-тест `ChatsListPage` в `test/presentation/pages/chats_list_page/chats_list_page_test.dart`: loading/empty/filled/search-empty/offline/error; тап→`RoutePlaceholderPage`; десктоп выбор→highlight без push; no-selection слот (зависит от T033).
- [ ] T038 [P] [US3] Golden-тест `ChatsListPage` (light/dark; loading/empty/filled/search-empty/offline; мобайл + десктоп list-detail) в `test/presentation/pages/chats_list_page/chats_list_page_golden_test.dart` + бейзлайны (spinner `settle:false`) (зависит от T033).
- [ ] T039 [P] [US3] Unit-тест `DateFormatter.relative` в `test/general/formatters/date_formatter_test.dart`: границы лестницы (now/<60s, min, h, Yesterday, `d MMM` этот год, `d MMM y` прошлый) (зависит от T030).
- [ ] T040 [P] [US3] Widget+golden тест `AppSearchFieldWidget` (ввод/`onChanged`) в `test/presentation/widgets/chat/app_search_field_widget_*.dart` + бейзлайны (зависит от T031).
- [ ] T041 [P] [US3] Тест мок-репозитория чатов (`ChatRepositoryImpl` → `RepositoryResult` success + пагинация + `search`-фильтр) в `test/data/repository/chat/chat_repository_impl_test.dart` (зависит от T029).

**Checkpoint**: US3 независимо тестируема; реальная композиция таба Chats; единственная заглушка-назначение — 5.2.

---

## Phase 6: Polish & Cross-Cutting Concerns

**⚠️ T042 и T043 — БЛОКИРУЮЩИЕ для «M3 done», НЕ опциональный polish** (Принцип II/III: дрейф блюпринта/спек чинится в этом же change-set; иначе остаётся живое нарушение конституции). Остальное (T044–T046) — финализация.

- [ ] T042 [P] **Reconciliation блюпринта** (Принцип III): обновить `docs/blueprints/mobile/05-presentation-layer.md` §6.5/§6 под реальный `TabBarShell` (kit `AppBottomBarWidget`/`AppCreateFabWidget` + локальный `AppTab`-state, не `AppRootBloc`) и **desktop list-detail** (сейчас доки говорят «desktop = rail + единый body, нет list-detail»).
- [ ] T043 [P] **Reconciliation спек** (Принцип II): дополнить desktop-секции locked per-screen спек — `docs/design/spec/screens/{tab-bar-shell,chats-list,settings-root}.md` — десктоп-раскладкой из авторитетного корпуса (`nox-desktop-screens/{01-chats,02-settings}.md`): list-detail (rail+list-pane+detail/thread-pane), desktop no-reveal, Logout→Splash (пометить, что **оба** корпуса дрейфят на Login).
- [ ] T044 [P] Обновить `docs/roadmap.md`: отметить `4.1`/`5.1`/`7.1` `[x]` в таблице M3, обновить счётчик прогресса (11 → 14 / 17), добавить новые блоки в реестр §6 (адаптивный шелл `TabBarShell`/list-detail; `AppIdentityCardWidget`/`AppLogoutDialogWidget`; relative-time форматтер; chats-вертикаль), зачеркнуть Q4 (Logout → Splash — решено).
- [ ] T045 [P] Добавить 3 экрана M3 (`TabBarShell`/`SettingsRootPage`/`ChatsListPage`) в `test/presentation/widgets/accessibility_test.dart` (tap-targets ≥48, `textScaler 2.0` без overflow).
- [ ] T046 Полный `make gate` (analyze без ошибок, widget+bloc-тесты) + `make golden-verify` для всех новых goldens; устранить дрейф. Дополнительно (FR-006/SC-008): grep-проверить маркеры `TODO(backend):`/`TODO(M4):` у всех заглушек (chats transport/cache, identity wipe, QR encoding, 5.2 thread, system-back) и отсутствие кириллицы в UI-строках `lib/presentation` (`grep -rPn "[\x{0400}-\x{04FF}]" lib/presentation`).

---

## Dependencies & Execution Order

- **Setup (Phase 1)** → **Foundational (Phase 2)** → истории (Phase 3–5) → **Polish (Phase 6)**.
- **Foundational блокирует все истории**: микрокопия (T002) — US2/US3; темы стоковых компонентов (T003) — US1 (rail)/US3 (search/banner/badge); `AppListDetailWidget` (T004) — US2/US3 (десктоп).
- **Истории независимы по коду** и тестируемы по отдельности (standalone `routeDemo`). Интеграция в шелл — задачи T019 (US2) и T034 (US3) подменяют тело таба в `TabBarShell`; шелл (US1) на старте хостит существующие плейсхолдеры → US1 — самостоятельный MVP.
- **Общие файлы — последовательно (НЕ параллелить между историями)**: `screens_gallery_page.dart` (T008→T020→T035 + его тест); `tab_bar_shell_widget.dart` (T007 create → T019 → T034 swap).
- Внутри истории: domain/data → BLoC/виджеты → страница → интеграция в шелл → активация Галереи → тесты. Порядок приоритетов: US1(P1) → US2(P2) → US3(P3).
- Переиспользуются существующие (без новых задач): `AppBottomBarWidget`/`AppCreateFabWidget`/`AppWordmarkWidget`/`AppSplashHairlineWidget`/`AppThemeToggle`, `AppChatItemWidget`/`AppAvatarWidget`/`AppEmptyContentWidget`/`AppErrorWidget`/`AppProgressWidget`/`AppLabeledFieldWidget`/`AppSpinnerWidget`, `showAppBanner`/`showAppSnackBar`, `debounceRestartable()`, `PagingStateExt.applyPage`, `OnboardingMockData.takenUsernames`, `RoutePlaceholderPage`/`CreateChatPage`/`SplashPage`/M1-подэкраны `.route()`, `Assets.svg.illustrations.emptyChats`.

## Parallel Execution Examples

- **Foundational**: T002 ∥ T003 ∥ T004 (разные файлы); затем T005 (тест контейнера).
- **US1**: T006 → T007 → T008; тесты T009 ∥ T010 ∥ T011.
- **US2**: T012 ∥ T013 ∥ T014 ∥ T015 → T016; T017 ∥ (T012–T016); затем T018 → T019 → T020; тесты T021 ∥ T022 ∥ T023 ∥ T024 ∥ T025 ∥ T026.
- **US3**: T027 → T028 → T029; T030 ∥ T031 ∥ (T027–T029); затем T032 → T033 → T034 → T035; тесты T036 ∥ T037 ∥ T038 ∥ T039 ∥ T040 ∥ T041.
- **Polish**: T042 ∥ T043 ∥ T044 ∥ T045; затем T046 (полный gate — последний).

## Implementation Strategy

- **MVP = User Story 1 (Tab-bar shell)** — первая поставка (предпосылки: Setup + Foundational T001–T005). Адаптивный шелл (bottom-bar↔rail, `IndexedStack`, `+`→реальный 6.1, back), открывается из Галереи, на плейсхолдер-табах; вводит несущий каркас приложения. STOP & VALIDATE независимо. (Примечание: FR-008/SC-005 «реальная композиция» полностью выполняется только после US2+US3 — на US1-MVP табы ещё плейсхолдеры; это приёмка конца этапа, не конца US1.)
- **Инкременты**: US2 (Settings root — identity-card, Logout→Splash, desktop list-detail; подменяет Settings-таб) → US3 (Chats list — network-only вертикаль, relative-time, list-detail; подменяет Chats-таб). Каждая — самостоятельный тестируемый прирост, отмечаемый в `docs/roadmap.md`.
- **Reconciliation (Принцип II/III)** — в этом же change-set (T042/T043): блюпринт 05 §6.5/§6 + desktop-секции per-screen спек приводятся к десктоп-корпусу/реальному коду. **Если объём режется** — единственные кандидаты на M4: desktop list-detail (тогда T004/T042/T043 и desktop-ветки T018/T033 упрощаются до single-pane) — по согласованию с владельцем.
- После каждой истории — `make gate` зелёный + golden-бейзлайны (`make golden-update`). BLoC-конвенция: `executeLogic` всегда с `onError`; `bloc_test` ассертит bare-имена (`Initializing`/`Initialized`/`Error` для `ChatsListBloc`).
