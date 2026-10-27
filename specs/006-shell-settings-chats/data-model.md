# Data Model — Этап M3 (Шелл, корень настроек, список чатов)

M3 — первый этап с реальным **domain+data** слоем поверх presentation. «Модель»: (1) chats-вертикаль (network-only мок: `ChatModel` + конфиг + репозиторий), (2) BLoC-состояния (`ChatsListBloc` sealed + `PagingState`; `SettingsRootBloc` value-state), (3) presentation-энумы и наборы визуальных состояний. Реального транспорта/сервера/персистентности нет — данные мок (как Item-слайс). Существующие типы (`AppTab`, `AppRootBloc`, `ItemListBloc`, `OnboardingMockData`) переиспользуются, не затрагиваются.

## Domain / Data — chats-вертикаль (зеркалит Item-слайс)

| Тип | Файл | Поля / сигнатура | Назначение |
|---|---|---|---|
| `ChatModel` | `domain/model/chat/chat_model.dart` | `@freezed`: `id: String`, `name: String`, `lastMessagePreview: String`, `lastMessageAt: DateTime`, `unreadCount: int` (`@Default(0)`) | Элемент списка чатов. `*.freezed.dart` (+ `*.g.dart` если нужен JSON, как `ItemModel`). |
| `GetChatsConfig` | `domain/repository/chat/get_chats_config.dart` | `@freezed implements RepositoryConfig`: `{required int page, String? search}`; `.firstPage({String? search})`; `.nextPage({required int page, String? search})`; `static const pageSize=20`, `defaultPage=1` | Конфиг запроса (зеркалит `GetItemsConfig`; уже несёт slot `search`). |
| `ChatRepository` | `domain/repository/chat/chat_repository.dart` | `Future<RepositoryResult<(List<ChatModel>, PageMetadata)>> getChats({required GetChatsConfig config})` | Интерфейс репозитория (network-only carve-out). |
| `GetChatsApi` | `data/remote/api/chat/get_chats_api.dart` | `@lazySingleton`; `Future<…> execute({required GetChatsConfig config})` — синтезирует N мок-`ChatModel` + задержка + `PageMetadata`, фильтрует по `config.search` | Мок-источник (зеркалит `GetItemsApi`; **данные мок, без сервера**). |
| `ChatRepositoryImpl` | `data/repository/chat/chat_repository_impl.dart` | `@LazySingleton(as: ChatRepository, env: [dev, prod, test])` — оборачивает `GetChatsApi` в `BaseRepositoryHelper.execute` → `RepositoryResult<(List<ChatModel>, PageMetadata)>` | Реализация (зеркалит `ItemRepositoryImpl`). |

> Мок-набор чатов (синтез в `GetChatsApi`): достаточно строк для демонстрации Filled/Search/Search-empty/пагинации; имена/превью/время/unread — детерминированы. `unreadCount`: часть с `0` (без бейджа), часть с `>0`, ≥1 с `>99` (cap `99+`). `OnboardingMockData.takenChatNames` — отдельный набор (уникальность создания 6.1), не список чатов.

## BLoC — `ChatsListBloc` (5.1) — sealed-trio + PagingState (зеркалит `ItemListBloc`)

Пагинированный network-only список ⇒ **sealed**-state (не value-state). Только `*.freezed.dart`. Геттеры — в `extension`.

| Тип | Файл | Значения / поля | Назначение |
|---|---|---|---|
| `ChatsListState` | `bloc/chats_list_state.dart` | `@freezed sealed`: `.initializing() = Initializing`; `.initialized({required PagingState<String, ChatModel> pagingState, @Default('') String query, @Default(false) bool isOffline, String? selectedChatId, @Default(false) bool loadingInProgress}) = Initialized`; `.error({BaseRepositoryException? exception}) = Error` | Состояние списка. `selectedChatId` — десктоп list-detail. Геттеры (extension): `pagedItems`, `hasMore`, `isSearching => query.isNotEmpty`, `isSearchEmpty`. |
| `ChatsListScenario` (enum, debug) | `bloc/chats_list_state.dart` | `normal`, `empty`, `inlineError`, `fatal`, `offline` | Заглушечный сценарий загрузки — выбирается debug-контролом (за `kDebugMode && demo`); детерминированно воспроизводит состояния Empty / Inline-error / Fatal / Offline (FR-005/FR-053/SC-002). |
| `ChatsListEvent` | `bloc/chats_list_event.dart` | `@freezed sealed`: `.initialize() = Initialize`; `.loadChats({@Default(false) bool reset}) = LoadChats`; `.searchChanged(String query) = SearchChanged` (debounced); `.chatSelected(String id) = ChatSelected` (десктоп); `.setScenario(ChatsListScenario scenario) = SetScenario` (debug) | `searchChanged` → debounced re-fetch (`GetChatsConfig.search`). `setScenario` шейпит исход следующей загрузки: `empty` → пустая страница; `inlineError`/`fatal` → ошибка из (мок-)репозитория; `offline` → `isOffline:true` + кэш. |

- Паттерн: `super(const ChatsListState.initializing())`; `on<Initialize>` → emit `Initialized(pagingState: PagingState())` затем `add(loadChats(reset:true))`; `on<LoadChats>(transformer: sequential())`; `on<SearchChanged>(transformer: debounceRestartable())` → reset + reload; `getIt<ChatRepository>()`; `executeLogic(…, onError: (…) => emit(const ChatsListState.error()))`; `result.match(onData: applyPage, onError: …)`; `PagingStateExt.applyPage(keyExtractor: (c)=>c.id)`; re-check `state is Initialized` после `await`. Offline — debug-`setOffline`/мок (реального детектора нет) → `Initialized(isOffline:true)` + `showAppBanner('No connection')`, список из (мок-)кэша.

## BLoC — `SettingsRootBloc` (7.1) — value-state (зеркалит `SetUsernameBloc`)

Форма «всегда живая» ⇒ **value-state** (`@freezed abstract class … with _$…` + приватный `const ._();` + computed-getters). Только `*.freezed.dart`.

| Тип | Файл | Значения / поля | Назначение |
|---|---|---|---|
| `SettingsNameStatus` (enum) | `bloc/settings_root_state.dart` | `idle`, `checking`, `valid`, `invalidCharset`, `taken`, `raceTaken` | Статус inline name-edit (как `UsernameStatus`, без `prefilled`/`empty`/`submitting` — у настроек имя всегда есть). |
| `LogoutPhase` (enum) | `bloc/settings_root_state.dart` | `idle`, `confirm`, `loading`, `done` | Фаза logout (диалог/спиннер/переход на 1.1). |
| `SettingsOutcome` (enum, debug) | `bloc/settings_root_state.dart` | `success`, `raceTaken`, `inlineError`, `fatal` | Заглушечный исход save/logout (debug-переключатель). |
| `SettingsRootState` | `bloc/settings_root_state.dart` | `@Default(true) bool initialLoading`, `@Default('User7421') String name`, `@Default('') String draftName`, `@Default(false) bool editing`, `@Default(SettingsNameStatus.idle) status`, `@Default(false) bool idRevealed` (мобайл), `@Default(LogoutPhase.idle) logoutPhase`, `@Default(SettingsOutcome.success) outcome` | value-state. `initialLoading` — стартовое состояние (спиннер в позиции ID, остальной список доступен; FR-038); снимается в `Initialize` после фейкового `Future`. Геттеры: `canSave => status==valid`; `errorText` (invalidCharset→`usernameCharsetError`, taken/raceTaken→`nameTakenError`); `maskedId` = `idMask` (`••••••••`); `rawId` — зафиксированная мок-константа (длинная key-like строка, напр. `static const _mockRawId`), `name` по умолчанию `User7421` (как `SetUsernameBloc.defaultName`). |
| `SettingsRootEvent` | `bloc/settings_root_event.dart` | `.initialize()`, `.nameEditStarted()`, `.nameChanged(String)` (immediate charset), `.nameAvailabilityRequested(String)` (debounced), `.nameSubmitted()`, `.nameEditCancelled()`, `.idRevealToggled()` (мобайл), `.copyRequested()`, `.logoutRequested()`, `.logoutConfirmed()`, `.setOutcome(SettingsOutcome)` (debug), `.navigationHandled()` | charset — клиентский (как 2.3); availability — мок (case-sensitive, `OnboardingMockData.takenUsernames`). |

- Identity — **стаб**: `name` (default `User7421`, как `SetUsernameBloc.defaultName`), `rawId` — фикс. мок-строка; `maskedId` = `••••••••` (8 точек). На десктопе `idRevealed` не используется (`revealable=false`). Logout: `logoutRequested`→`confirm`; `logoutConfirmed`→`loading`(фейк `Future`, `executeLogic(onError:)`)→`done`→страница `Navigator.…(SplashPage.route())`.

## Presentation-энумы и переиспользуемое (без новых BLoC)

| Тип | Файл | Значения / поля | Назначение |
|---|---|---|---|
| `AppTab` (reuse) | `widgets/shell/app_bottom_bar_widget.dart` | `enum AppTab { chats, settings }` | Состояние активного таба `TabBarShell` (локальный `_active` + setState; **без** нового enum). |
| `OnboardingMockData.takenUsernames` (reuse) | `general/onboarding_mock_data.dart` | `const Set<String>` (case-sensitive) | Источник uniqueness для inline name-edit 7.1. |

> Debug-исходы (`SettingsOutcome`, `ChatsListScenario` через `ChatsListEvent.setScenario`) — за `kDebugMode` (строки Галереи 5.1/7.1 открыты через `routeDemo`); в продуктовом флоу заменяются реальным репозиторием (`// TODO(backend):`). 4.1 (`TabBarShell.route`) — без debug-исходов (презентационный). На 5.1 Empty / Inline-error / Fatal / Offline воспроизводятся `setScenario` (Search-empty — естественно, непустым запросом без совпадений).

## Состояния по экранам (визуальный вокабуляр)

Все состояния воспроизводимы на заглушках (мок-репозиторий + debug-контролы).

### 4.1 Tab-bar shell (`TabBarShell`, без BLoC)
- `Chats-active` / `Settings-active`: `IndexedStack` body, выбранный таб `primary`+filled; `tabFade` 150мс.
- Мобайл: `BottomAppBar`(вырез) + center-docked `+` FAB. Десктоп (≥840): `NavigationRail` + leading `+` FAB.
- `Pushed`: поверх шелла открыт экран на весь экран (нижняя панель скрыта) — 6.1, 7.2–7.7, 5.2-плейсхолдер. `+`→6.1: мобайл fullscreen push / десктоп модальный `Dialog` (page self-adapts).
- Back: не-Chats→Chats; Chats→`SystemNavigator.pop` (превью: заглушено). Re-tap Chats→scroll-to-top; Settings→no-op.

### 5.1 Chats list (`ChatsListPage` / `ChatsListBloc`)
- `Initial-loading` (`Initializing`): centered `AppProgressWidget`.
- `Empty`: `AppEmptyContentWidget(emptyChats, 'No chats yet', 'Tap + to create the first one.')`.
- `Filled` (`Initialized`): `PagedListView` из `AppChatItemWidget` (avatar + name + preview + relative-time + unread-бейдж `primary`, скрыт при 0, cap `99+`).
- `Searching`: непустой `query` → фильтрация (debounced re-fetch). `Search-empty`: 0 совпадений → `No chats found`.
- `Offline` (`isOffline`): постоянный `MaterialBanner` `No connection` (`showAppBanner`), список из (мок-)кэша.
- `Inline-error`: `MaterialBanner` `Could not load chats. Pull to refresh.` (или `AppErrorWidget(onTryAgain:)` для first-page).
- `Fatal` (`Error`): → 3.1 (embedded) / `AppErrorWidget`.
- Тап по элементу (мобайл) / выбор строки (десктоп) → 5.2-плейсхолдер (`RoutePlaceholderPage('Chat thread (5.2)')`).
- Десктоп: rail + list-pane 360 (pane-header + `AppSearchFieldWidget`) + thread-pane; выбор → highlight `secondaryContainer` без push; no-selection → `Select a chat` / `Choose a conversation on the left, or press + to start a new one.`; thread content = **M4-плейсхолдер**.

### 7.1 Settings root (`SettingsRootPage` / `SettingsRootBloc`)
- `Initial-loading`: `CircularProgressIndicator` в позиции ID, остальной список доступен.
- `Loaded`: identity `Card` (avatar + Name + `Your ID`) + плоский список `AppSettingsNavRowWidget` (`Notifications`/`Appearance`/`Language`/`Terms`/`About`) + `Log out` (`ColorScheme.error`).
- `Name-editing`: inline `AppLabeledFieldWidget(maxLength:32)` + counter + suffix-спиннер; charset (`invalidCharset`) / `checking` / `valid` / `taken` (`This name is taken`); save Enter/Done/blur при valid; пустое → не меняет; Cancel → прежнее.
- `Identifier`: мобайл маска `••••••••` + `Show/Hide` (raw monospace wrap) + `Copy` + `Show QR`; **десктоп — без `Show/Hide`** (всегда маска) + inline account-QR + `Copy` + `Show QR`.
- `QR-overlay`: fake-QR на brand-fixed светлой поверхности (`qrSurface`/`qrInk`); мобайл — modal bottom sheet (`Your ID QR`, `Close`), десктоп — центр. `Dialog`. raw-ID текстом нет.
- `Copy`: → буфер + snackbar `Copied to clipboard`.
- `Logout-confirm` → `AlertDialog`; `Logout-loading` → спиннер в кнопке (модален) → `1.1 Splash`.
- `Inline-error` (snackbar/`errorText`); `Fatal` → 3.1.
- Десктоп: list-detail — menu-pane 340 + detail-pane ≤680 (контент M1-`…Body` без AppBar/back, swap без push).

## Связи и инварианты

- `ChatsListBloc` — sealed-trio (зеркало `ItemListBloc`): `executeLogic` **всегда с `onError`** (иначе исключение глотается → нет error-state); `transformer: sequential()` (load) / `debounceRestartable()` (search); `PagingStateExt.applyPage(keyExtractor: (c)=>c.id)`; re-check `state is Initialized` после `await`; `getIt<ChatRepository>()`.
- `SettingsRootBloc` — value-state + `copyWith` (форма всегда интерактивна); name-edit charset клиентский + availability мок (case-sensitive); `executeLogic(onError:)` на logout/availability. `Initialize` снимает `initialLoading` после фейкового `Future` (спиннер в позиции ID). Десктоп list-detail: detail-pane по умолчанию (до выбора пункта) = блок идентичности (account).
- `TabBarShell` — `StatefulWidget` без BLoC; `AppTab _active` + `IndexedStack` (сохранение табов).
- Selection (десктоп) — **view-state** двухпанельной раскладки (`selectedChatId` / локально в 7.1), а не nav-side-effect (§5.6 касается nav-эффектов, не selection-state).
- Композиция реальна: `+`→`CreateChatPage.route()` (self-adapts); строки 7.1→реальные `7.2–7.7 .route()`; Logout→`SplashPage.route()`. Единственная заглушка-назначение — `RoutePlaceholderPage('Chat thread (5.2)')` (`// TODO(M4):`).
- Светлая QR-поверхность (`NoxBrand.qrSurface`/`qrInk`, §9.10) — вне `ColorScheme` (второе brand-fixed исключение); всё прочее темизируется.
- Relative-time форматируется в странице/`DateFormatter.relative` — `AppChatItemWidget.time` принимает готовую строку.
