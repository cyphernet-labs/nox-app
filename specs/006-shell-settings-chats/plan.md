# Implementation Plan: Экраны этапа M3 — Шелл, корень настроек, список чатов

**Branch**: `006-shell-settings-chats` | **Date**: 2026-06-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/006-shell-settings-chats/spec.md`

## Summary

Реализовать три экрана этапа M3 — **Tab-bar shell / адаптивный шелл (4.1)**, **Settings root / корень настроек (7.1)**, **Chats list / список чатов (5.1)** — которые впервые **собирают готовые экраны в скелет приложения**. Адаптив — width-driven по `Constants.railBreakpoint` (840dp): мобайл — `BottomAppBar` с вырезом + center-docked `+` FAB; десктоп — `NavigationRail` + leading FAB и двухпанельный **list-detail**. M3 вживляет реальную композицию: шелл хостит реальные 5.1 + 7.1 как табы; `+` открывает реальный 6.1 (width-adaptive — push на мобайле / `Dialog` на десктопе); строки 7.1 открывают реальные 7.2–7.7; Logout ведёт на реальный 1.1 Splash. **Единственная заглушка-назначение** — лента чата 5.2 (этап M4): тап по чату (мобайл) / thread-pane (десктоп) показывают лёгкий плейсхолдер. Бэкенд (реальный транспорт/сервер) вне scope — данные мок.

Технический подход (по верифицированному коду, research-проход 2026-06-20):
- **4.1 `TabBarShell`** — `StatefulWidget` **без BLoC** (локальный `AppTab _active` + `IndexedStack`, сохранение состояния табов; `NoxDuration.tabFade`=150мс). Карв-аут блюпринта 05 §5/§6 (как Feature-001 `AppShell`). Композирует **Feature-003** kit: `AppBottomBarWidget`(`active`,`onSelect`) + center-docked `AppCreateFabWidget`(`onPressed`) на мобайле; `NavigationRail` + leading FAB на десктопе. Заменяет верификационный, **не смонтированный** `AppShell` как живой шелл.
- **7.1 `SettingsRootPage` + `SettingsRootBloc`** — Freezed **value-state** (как `CreateChatState`/`SetUsernameState`: `abstract class … with _$…` + приватный `._()` + computed-getters). Inline name-edit **переиспользует** валидацию 2.3 (charset `[A-Za-z0-9._-]`, ≤32, case-sensitive uniqueness против `OnboardingMockData.takenUsernames`, `debounceRestartable()` 300мс). Identity-card (новый `AppIdentityCardWidget`, параметризуемый `revealable`/inline-QR по раскладке) + logout-диалог (`AppLogoutDialogWidget`) + settings-nav-строка (`AppSettingsNavRowWidget`). Десктоп list-detail (menu-pane ≈340 + detail-pane ≤680, swap без push).
- **5.1 `ChatsListPage` + `ChatsListBloc`** — **network-only мок-репозиторий чатов** (carve-out: `ChatModel` + мок-`GetChatsApi` + `ChatRepository`/`Impl` через DI), `ChatsListBloc` зеркалит `ItemListBloc` — **sealed**-trio `Initializing/Initialized/Error`, `PagingState`-в-bloc, `transformer: sequential()`, `executeLogic(onError:)`, `PagingStateExt.applyPage`. Reuse `AppChatItemWidget`/`AppAvatarWidget`/state-виджеты + `showAppBanner` (офлайн). **Расширить** `DateFormatter` относительным временем (лестница `overview.md`). Десктоп list-detail (rail + list-pane 360 + thread-pane = M4-плейсхолдер).

**Новые зависимости не добавляются**: `qr_flutter` не подключается — QR на 7.1 рисуется как нейтральный fake-QR на brand-fixed светлой поверхности (`NoxBrand.qrSurface` #FFFFFF / `qrInk` #0C0C0C, design-system §9.10 — **второе** brand-fixed исключение проекта, уже зафиксированное в спеке); относительное время — на уже доступном `intl`; debounce — `debounceRestartable()` (rxdart). Микрокопия EN через `TextConstants` (≈14 для 7.1 + ≈4 для 5.1; новых SVG-иконок **не требуется** — все нужные глифы есть).

## Technical Context

**Language/Version**: Dart `>=3.12.0 <4.0.0`, Flutter `3.44.1` (FVM-pinned), длина строки 140, стоковый `flutter_lints`.

**Primary Dependencies**: `flutter_bloc` 9.1.1, `bloc_concurrency` 0.3.0 (`sequential()` для пагинированной загрузки), `rxdart` 0.28.0 (`debounceRestartable()`), `freezed` 3.2.5 + `freezed_annotation`, `json_serializable` (для `ChatModel`/`ChatEntity`, как Item-слайс), `injectable`+`get_it` (DI для `ChatRepository`), `infinite_scroll_pagination` v5 (`PagingState`-в-bloc — **5.1 первый реальный потребитель**), `flutter_screenutil`, `flutter_svg`, `flutter_gen`, `intl` 0.20.2 (относительное время), `package_info_plus` (reuse в About). **Новые зависимости не добавляются** (`qr_flutter` — Фаза 2; QR — fake-stub).

**Storage**: Реальной персистентности нет. Список чатов — **network-only мок-репозиторий** (мок-`GetChatsApi` синтезирует данные + задержку + `PageMetadata`, как `GetItemsApi`; без Sembast-кэша в M3 — cache-first слой backend-фазы). Identity (имя `User<random>` + raw-ID) — стаб. BLoC-состояния — in-memory на время жизни страницы. Выбранный таб/чат не персистятся.

**Testing**: `flutter_test` + `bloc_test` (для `ChatsListBloc` sealed-trio и `SettingsRootBloc` value-state) + `mockito` (только; mocktail запрещён); golden через локальный харнес `test/utils/golden.dart` (Apple Silicon/macOS, тег `golden`, вне CI). Обязателен `pumpApp`. BLoC-тесты ассертят **bare**-имена сабстейтов (`Initializing`/`Initialized`/`Error`); `Error` эмитится только при переданном `onError`.

**Target Platform**: iOS, Android, Windows, Linux, macOS (web вне scope). Один пакет `nox_app`.

**Project Type**: Кросс-платформенное Flutter-приложение (single package), Clean Architecture слоями-папками. M3 затрагивает **presentation** (3 экрана + 2 BLoC + шелл + виджеты) + **domain** (`ChatModel`/`ChatRepository` интерфейс) + **data** (мок-`GetChatsApi` + `ChatRepositoryImpl`) + **di** (регистрация репозитория) + точечно **design** (темы стоковых компонентов, микрокопия) + **general** (relative-time форматтер).

**Performance Goals**: 60 fps; `NoxDuration.tabFade`=150мс на переключении табов (`IndexedStack`); пагинированная загрузка (`sequential()`); debounced поиск/проверка имени (~300мс `switchMap` отменяет устаревшие); спиннеры на `NoxDuration`/`NoxEasing`.

**Constraints**: Токен-дисциплина (нет сырых `Color`/`EdgeInsets`/`TextStyle`/overlay-литералов вне `lib/design/theme/`); иконки только SVG `NoxIcons`; микрокопия EN через `TextConstants`; адаптив width-driven по `Constants.railBreakpoint` (840dp) через `LayoutBuilder` (не Platform); **второе brand-fixed исключение** — светлая поверхность отображения QR на 7.1 (`NoxBrand.qrSurface` #FFFFFF / `qrInk` #0C0C0C, design-system **§9.10**; первое — тёмный splash 1.1, M1). Раздел §9.9 — это camera-overlay 2.2 (#FAFAFA/#000@55%), **не** путать с §9.10.

**Scale/Scope**: 3 экрана + 2 BLoC (`ChatsListBloc` sealed, `SettingsRootBloc` value-state) + `TabBarShell` (BLoC-less) + **chats-вертикаль** (`ChatModel`, `GetChatsConfig`, мок-`GetChatsApi`, `ChatRepository`/`Impl`, DI) + новые виджеты (`AppIdentityCardWidget`, `AppSettingsNavRowWidget`, `AppLogoutDialogWidget`, `AppListDetailWidget` двухпанельный контейнер, `AppQrSurfaceWidget` fake-QR, `AppSearchFieldWidget` редактируемый поиск) + извлечение body-виджетов M1-подэкранов (для desktop detail-pane) + 4 новые темы стоковых компонентов + relative-time форматтер + ≈18 микрокопий + активация 3 строк Галереи. Тесты widget+golden на каждый экран/виджет + bloc_test на 2 BLoC + gallery-тест.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Принцип | Оценка | Обоснование |
|---|---|---|
| **I. Приватность и E2EE** | ✅ PASS | Экраны M3 не работают с содержимым/PII. Identity (имя/ID) — стаб, не валидируется/не отправляется. **Усиление приватности:** на десктопе raw-ID **не раскрывается** (`revealable=false`, всегда маска + inline account-QR) — минимизация раскрытия секрета (Clarifications Q2). Logout → 1.1 Splash после (заглушенной) **полной очистки локальных данных** — соответствует Принципу I. Нет аналитики/логов с PII. |
| **II. Спека/дизайн-корпус — источник истины** | ✅ PASS (с зафиксированными reconciliation) | Строим по locked `docs/design/spec/screens/{tab-bar-shell,settings-root,chats-list}.md` + **авторитетному десктоп-корпусу** `nox-desktop-screens/{01-chats,02-settings}.md` + `spec.md`. **Зафиксированные расхождения, разрешаемые осознанно в этом change-set** (см. Complexity Tracking): (а) **desktop list-detail** — locked per-screen спеки mobile-shaped (у `tab-bar-shell.md` нет desktop-секции), а блюпринт 05 §6.5 говорит «desktop = rail + единый body, нет list-detail»; десктоп-list-detail взят из авторитетного десктоп-корпуса + roadmap-заголовка M3 + owner-решения (Clarifications) → реконсайл доков; (б) **Logout → Splash 1.1** (locked `settings-root.md`), хотя **оба** корпуса (`02-settings`, `7-1-settings`) дрейфуют на «→ Login» — следуем locked-спеке; (в) **desktop no-reveal** — locked-спека даёт `Show/Hide` безусловно (mobile-shaped), десктоп-корпус — «no secret reveal»; реконсайл параметризацией виджета. Out-of-scope (5.2 лента) не расширяется — остаётся плейсхолдером. |
| **III. Архитектурный блюпринт обязателен** | ✅ PASS (с reconciliation блюпринта) | Страницы по конвенции (`pages/<page>_page/`, `route()`/`routeDemo()`, токены, `NoxIcons`, `TextConstants`). **`ChatsListBloc` — network-only carve-out** (открытый список чатов — первая реальная такая фича по блюпринту 00/05): зеркалит `ItemListBloc` (sealed-trio, `PagingState`-в-bloc, `sequential()`, `executeLogic(onError:)`, `PagingStateExt.applyPage`) поверх `ChatRepository` через `getIt` — **не** inline in-memory список. `SettingsRootBloc` — value-state форма (как `SetUsernameBloc`). **`TabBarShell` — `StatefulWidget` без BLoC** (карв-аут 05 §5/§6, как `AppShell`). **Reconciliation (Принцип III, тот же change-set):** блюпринт 05 §6.5/§6 устарел — говорит «target tab-state — `AppRootBloc`» и предписывает сырые стоковые `NavigationRail`/`BottomAppBar`, тогда как живой kit — `AppBottomBarWidget`, а M3 вводит desktop list-detail; §6.5/§6 правится под реальный шелл в этом же change-set. |
| **IV. Верность дизайн-системе** | ✅ PASS | M3 light+dark, только токены. Иконки — SVG `NoxIcons`: все нужные глифы **уже есть** (`forum`/`forumFill`/`settings`/`settingsFill`/`add`/`arrowBack`/`edit`/`contentCopy`/`qrCode`/`visibility`/`visibilityOff`/`search`/`noPhotography`) — **новых SVG не требуется** (`chevron`/`logout` отсутствуют, но спека использует icon-less ListTile в `ColorScheme.error`). **Второе brand-fixed исключение** — светлая QR-поверхность 7.1 (`NoxBrand.qrSurface`/`qrInk`, §9.10) вне `ColorScheme`. Недостающие темы стоковых компонентов (`SearchBarThemeData`, `MaterialBannerThemeData`, `BadgeThemeData`→`primary`, `NavigationRailThemeData`) **добавляются в `nox_component_themes.dart`** (тематизация, не хардкод). |
| **V. Языковая дисциплина** | ✅ PASS | Спека/план — RU; код/идентификаторы/коммиты — EN; UI-микрокопия — EN (`TextConstants`, ≈18 новых строк); RU в UI отсутствует. |

**Gate (до Phase 0): PASS.** Нарушений-блокеров нет. Два пункта вынесены в Complexity Tracking как **осознанные reconciliation** (desktop list-detail; chats network-only — последний фактически *устраняет* потенциальное нарушение, выбирая блюпринт-корректный путь). Введение `ChatsListBloc`/`SettingsRootBloc` — следование блюпринту, не усложнение.

**Re-check (после Phase 1 design): PASS.** Design-артефакты не вводят новых зависимостей. `ChatsListBloc` (sealed + `PagingState`) и `SettingsRootBloc` (value-state) согласованы с блюпринтом 05. Desktop list-detail и selection-in-state — это **view-state двухпанельной раскладки** (выбор определяет содержимое detail-pane), а **не** транзиентный nav-эффект (§5.6 касается nav-side-effects вида «push X», не selection). Reconciliation блюпринта 05 §6.5/§6 и desktop-секций per-screen спек запланированы как задачи (Phase 2 tasks). Спека↔блюпринт↔код приводятся к консистентности в этом change-set (Принцип II/III). Готово к `/speckit-tasks`.

## Project Structure

### Documentation (this feature)

```text
specs/006-shell-settings-chats/
├── plan.md              # Этот файл (/speckit-plan)
├── research.md          # Phase 0 — технические решения (verified против lib/)
├── data-model.md        # Phase 1 — chats-вертикаль + BLoC-состояния/энумы/визуальный вокабуляр
├── quickstart.md        # Phase 1 — как запустить и проверить
├── contracts/           # Phase 1 — UI-контракты
│   ├── navigation.md     #   route()/routeDemo(), активация Галереи, композиция (+→6.1, rows→7.2-7.7, logout→1.1, 5.1→5.2)
│   └── widgets.md        #   публичные API новых виджетов + BLoC event/state + темы + извлечённые body-виджеты
├── checklists/
│   └── requirements.md  # из /speckit-specify + /speckit-clarify (16/16)
└── tasks.md             # Phase 2 (/speckit-tasks — НЕ создаётся этим планом)
```

### Source Code (repository root)

```text
lib/presentation/widgets/shell/
├── tab_bar_shell_widget.dart                  # NEW: TabBarShell (StatefulWidget, БЕЗ BLoC) — AppTab _active + IndexedStack(tabFade);
│                                              #      мобайл: Scaffold(AppBottomBarWidget + centerDocked AppCreateFabWidget); десктоп: Row[NavigationRail+leading FAB, body]
│                                              #      hosts ChatsListPage (tab 0) + SettingsRootPage (tab 1); '+' → CreateChatPage.route() (page self-adapts)
├── app_navigation_rail_widget.dart            # NEW: десктоп rail (forum/forumFill, settings/settingsFill) + leading AppCreateFabWidget (kit-аналог AppBottomBarWidget)
└── app_list_detail_widget.dart                # NEW: двухпанельный контейнер (list-pane fixed + detail-pane Expanded), highlight без push; no-selection слот

lib/presentation/pages/
├── chats_list_page/
│   ├── chats_list_page.dart                   # NEW ChatsListPage: route()/routeDemo(); мобайл AppBar(NOX wordmark+hairline)+SearchField+PagedListView(RefreshIndicator); десктоп list-pane 360 + thread-pane (M4 placeholder)
│   └── bloc/
│       ├── chats_list_bloc.dart               # NEW BLoC (sealed, зеркалит ItemListBloc): sequential(), executeLogic(onError:), PagingStateExt.applyPage; getIt<ChatRepository>
│       ├── chats_list_event.dart              # initialize / loadChats(reset) / searchChanged(debounced) / chatSelected(desktop) / setOffline(debug)
│       └── chats_list_state.dart              # @freezed sealed: Initializing / Initialized(pagingState, query, isOffline, selectedChatId) / Error
└── settings_root_page/
    ├── settings_root_page.dart                # NEW SettingsRootPage: route()/routeDemo(); мобайл Scaffold(AppBar 'Settings')+ListView(identity Card + nav-rows + Log out); десктоп list-detail (menu-pane 340 + detail-pane 680)
    └── bloc/
        ├── settings_root_bloc.dart            # NEW BLoC (value-state, зеркалит SetUsernameBloc): name-edit charset+availability (debounceRestartable), logout(fake Future), copy/QR
        ├── settings_root_event.dart           # initialize / nameEditStarted / nameChanged / nameSubmitted / logoutRequested / logoutConfirmed / setOutcome(debug) / navigationHandled
        └── settings_root_state.dart           # @freezed value-state: name, editing, status(idle/checking/...), identifier(masked/raw), logoutPhase; getters errorText/canSave

lib/presentation/widgets/settings/
├── app_identity_card_widget.dart              # NEW: filled Card — generated avatar (noxInitials/noxAvatarColor) + Name block (inline-edit) + 'Your ID' block; параметры revealable (мобайл true/десктоп false), showInlineQr (десктоп)
├── app_settings_nav_row_widget.dart           # NEW: ListTile (title + onTap, опц. trailing) — строка раздела настроек
├── app_logout_dialog_widget.dart              # NEW: AlertDialog confirm (Log out? / message / Log out·Cancel) + logout-loading (спиннер в кнопке, модален)
└── app_qr_surface_widget.dart                 # NEW: fake-QR на brand-fixed светлой поверхности (NoxBrand.qrSurface/qrInk); bottom-sheet (мобайл) / Dialog (десктоп)

lib/presentation/widgets/chat/
└── app_search_field_widget.dart              # NEW: РЕДАКТИРУЕМОЕ поле поиска (AppSearchBarWidget — display-only, не editable) + onChanged (debounced снаружи)

lib/presentation/pages/{notifications,appearance,language,about}_page/
└── *_body.dart (или public *Body)             # REFACTOR: извлечь body M1-подэкранов в ПУБЛИЧНЫЙ переиспользуемый виджет (TermsBody уже есть приватный — сделать public);
                                              #          мобайл = AppDetailScaffoldWidget(body: …Body) (как сейчас), десктоп 7.1 detail-pane = тот же …Body без AppBar/back

lib/domain/
├── model/chat/chat_model.dart                 # NEW @freezed ChatModel{id, name, lastMessagePreview, lastMessageAt(DateTime), unreadCount}
└── repository/chat/{chat_repository.dart, get_chats_config.dart}  # NEW ChatRepository интерфейс + GetChatsConfig{page, search} (зеркалит GetItemsConfig)

lib/data/
├── remote/api/chat/get_chats_api.dart         # NEW @lazySingleton мок-источник: синтезирует N мок-чатов + задержку + PageMetadata (как GetItemsApi)
└── repository/chat/chat_repository_impl.dart  # NEW @LazySingleton(as: ChatRepository, env:[dev,prod,test]) → RepositoryResult<(List<ChatModel>, PageMetadata)>

lib/general/
├── formatters/date_formatter.dart             # + static String relative(DateTime, {DateTime? now}) — лестница now/5 min/2 h/Yesterday/12 May/12 May 2025 (intl)
└── text_constants.dart                        # + ≈14 (7.1) + ≈4 (5.1) EN-строк; reuse chats/settings/searchHint/appName/noConnection/comingSoon/actionCancel/tooltipBack/usernameLabel/usernameCharsetError/nameTakenError/settings*Title/loginIdLabel

lib/design/theme/nox_component_themes.dart     # + SearchBarThemeData, MaterialBannerThemeData, BadgeThemeData(bg: cs.primary), NavigationRailThemeData; assemble in AppTheme._build

lib/presentation/pages/screens_gallery_page/
└── screens_gallery_page.dart                  # активировать строки 4.1 (TabBarShell.route) / 5.1 (ChatsListPage.routeDemo) / 7.1 (SettingsRootPage.routeDemo)

# Переиспользуется (без изменений): AppBottomBarWidget/AppCreateFabWidget/AppWordmarkWidget/AppSplashHairlineWidget/AppWindowTitlebarWidget/AppThemeToggle,
#   AppChatItemWidget/AppAvatarWidget/AppEmptyContentWidget/AppErrorWidget/AppProgressWidget/AppSpinnerWidget, showAppBanner/showAppSnackBar,
#   AppLabeledFieldWidget (inline name-edit), debounceRestartable(), PagingStateExt.applyPage, OnboardingMockData.takenUsernames,
#   RoutePlaceholderPage (5.1→5.2 / desktop thread-pane), CreateChatPage.route() ('+'), Notifications/Appearance/Language/Terms/About .route() (7.1 rows, мобайл push), Assets.svg.illustrations.emptyChats.

test/presentation/widgets/shell/              # widget+golden: TabBarShell (мобайл/десктоп), AppListDetailWidget, AppNavigationRailWidget
test/presentation/pages/{chats_list,settings_root}_page/  # widget + *_golden_test (light/dark, состояния) + bloc/ bloc_test
test/presentation/widgets/{settings,chat}/    # widget+golden на новые виджеты
test/data|domain/…/chat/                       # unit-тест мок-репозитория чатов (опц.) + relative-time форматтера
```

**Structure Decision**: Один пакет `nox_app`, Clean Architecture слоями-папками. M3 — первый этап, добавляющий **domain+data** (chats-вертикаль) поверх presentation. `TabBarShell` — в `widgets/shell/` (BLoC-less, как kit-композитор). Экраны — папки-страницы со статическим `route()`/`routeDemo()` (роутера нет). `ChatsListPage`/`SettingsRootPage` владеют Freezed-BLoC (паттерн `CreateChatPage`: `late final _bloc` в `initState`, `close()` в `dispose`, `BlocProvider.value` + `BlocBuilder`/`BlocConsumer`). `ChatsListBloc` — **sealed-trio** + `PagingState` (как `ItemListBloc`); `SettingsRootBloc` — **value-state** (как `SetUsernameBloc`). Каждый tab-root доступен и внутри шелла (реально), и standalone из Галереи (`routeDemo`). Тесты deep-mirror под `test/`.

## Complexity Tracking

> Заполнено: два пункта требуют осознанной reconciliation доков (Принцип II/III) — оба санкционированы owner-решением (Clarifications) и roadmap-заголовком M3.

| Расхождение / усложнение | Зачем нужно | Почему простая альтернатива отклонена |
|---|---|---|
| **Desktop list-detail (4.1/5.1/7.1)** — двухпанельная list-detail раскладка с выбором без push. Locked per-screen спеки mobile-shaped (`tab-bar-shell.md` без desktop-секции), блюпринт 05 §6.5 говорит «desktop = rail + единый body, нет list-detail». | **Заголовок этапа M3** («адаптивный шелл + **list-detail**»), owner-решение (Clarifications Q2 «Каркас + плейсхолдер ленты»), и **авторитетный десктоп-корпус** `01-chats`/`02-settings` детально описывает её (design-fidelity verify: «matches desktop corpus exactly»). | Single-pane десктоп (только rail + body) — отклонено: противоречит roadmap-заголовку, owner-решению и десктоп-корпусу. Reconciliation: правим блюпринт 05 §6.5/§6 + добавляем desktop-секции в per-screen спеки под десктоп-корпус **в этом же change-set** (Принцип II/III; задачи в `tasks.md`). |
| **Chats list = network-only мок-вертикаль** (`ChatModel`+`GetChatsApi`+`ChatRepository`/`Impl`), а не inline in-memory список. | Блюпринт 00/05 прямо называет открытый список чатов **первой реальной network-only фичей**; `ChatsListBloc` обязан резолвить `getIt<ChatRepository>` → `RepositoryResult` + `PagingState`-в-bloc (зеркало `ItemListBloc`). | Inline in-memory список в bloc — отклонено: нарушает network-only инвариант блюпринта (потребовал бы Complexity-обоснования). Мок-вертикаль = блюпринт-корректный путь, повторяет проверенный Item-слайс, без реального сервера (данные мок) — совместимо с «backend вне scope». |
