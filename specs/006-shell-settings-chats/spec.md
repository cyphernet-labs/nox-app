# Feature Specification: Экраны этапа M3 — Шелл, корень настроек, список чатов

**Feature Branch**: `006-shell-settings-chats`

**Created**: 2026-06-20

**Status**: Draft

**Input**: User description: "Запланировать работу из `docs/roadmap.md` — Этап M3 — Шелл, корень настроек, список чатов ⟶ скелет приложения, адаптивный шелл + list-detail"

## Контекст фичи

Фаза 1 проекта (см. `docs/roadmap.md`) — сборка визуального слоя приложения по одному экрану; **интеграция с бэкендом вне scope**. Каркас «Галереи экранов» (этап M0), семь экранов M1 (Splash, Error, Appearance, Language, Notifications, Terms, About) и четыре экрана M2 (Login, QR scan, Set username, Create chat) уже готовы и открываются из Галереи (`ScreensGalleryPage`).

Эта фича закрывает **этап M3** — три экрана, которые впервые **собирают готовые экраны в скелет приложения**: **Tab-bar shell / адаптивный шелл (4.1)**, **Settings root / корень настроек (7.1)** и **Chats list / список чатов (5.1)**. Этап вводит несущие переиспользуемые блоки скелета:

- **Адаптивный шелл** — `TabBarShell` (мобайл: `BottomAppBar` с вырезом + центральный docked `+` FAB ↔ десктоп: `NavigationRail` + leading FAB; брейкпоинт `Constants.railBreakpoint` = 840dp) и контейнер **list-detail** для десктопа. Reuse `AppBottomBarWidget`/`AppCreateFabWidget`; сверяется с верификационным Feature-001 `AppShell` и заменяет его как живой шелл.
- **Карта идентичности** — `AppIdentityCardWidget` (блок имени с inline-edit + блок `Your ID` с маской/Show-Hide/Copy/Show QR) + `AppLogoutDialogWidget`; settings-nav-строки (`AppSettingsNavRowWidget`).
- **Форматтер относительного времени** — лестница `now` / `5 min` / `2 h` / `Yesterday` / `12 May` для списка чатов (переиспользуют 5.3/5.4 в M4).

**Ключевое отличие M3 от M1/M2.** До этого этапа каждый экран был полностью standalone (никакой меж-экранной навигации). M3 — этап, на котором экраны **начинают композироваться в реальный скелет**: шелл хостит реальные 5.1 и 7.1 как табы; центральная `+` открывает реальный 6.1; строки настроек открывают реальные 7.2–7.7; Logout ведёт на реальный 1.1 Splash. Заглушкой остаётся **только** ещё не построенная лента чата 5.2 (этап M4).

Каждый экран реализуется мультиплатформенно (мобайл + десктоп), со всеми визуальными состояниями на заглушечных данных, в соответствии с зафиксированными спеками `docs/design/spec/screens/` (`tab-bar-shell.md`, `settings-root.md`, `chats-list.md`) и десктоп/мобайл-корпусами (`nox-desktop-screens/screens/{01-chats,02-settings}.md`, `nox-mobile-screens/screens/{4-1-shell,5-1-chats,7-1-settings}.md`).

Реальная авторизация и хранение идентификатора, серверные проверки уникальности, реальный список чатов (транспорт/кэш), реальное создание чата, реальное QR-кодирование и продуктовый навигационный флоу (`1.1 → 2.1 → 2.3 → 4.1`) — отдельная (backend) фаза.

## Clarifications

### Session 2026-06-20

- Q: M3 — первый этап, где экраны перестают быть изолированными. Какие связи между готовыми экранами вживляем реально (не заглушка)? → A: **Связать всё готовое.** Шелл 4.1 хостит реальные 5.1 (Chats) + 7.1 (Settings) как табы; центральная `+` → реальный 6.1 (M2); строки 7.1 → реальные 7.2–7.7 (M1); Logout → реальный 1.1 Splash. Заглушка — только у не построенного 5.2 (лента, M4). Это естественный смысл «скелета приложения».
- Q: Заголовок этапа — «адаптивный шелл + list-detail», но десктоп-list-detail у 5.1 показывает справа ленту 5.2, которая ещё не построена (M4). Что рендерим в правой панели на десктопе? → A: **Каркас + плейсхолдер ленты.** Строим всю механику list-detail (rail + list-pane 360 + thread-pane, выбор строки = highlight `secondaryContainer` без push, состояние no-selection «Select a chat»). Контент ленты справа = лёгкий плейсхолдер «лента — в M4». Механика готова сейчас, контент 5.2 — в M4.
- Q: Logout — locked-спека `settings-root.md` ведёт на 1.1 Splash, а десктоп-корпус `02-settings` — на Login. Roadmap Q4 просит зафиксировать канон. → A: **Splash 1.1 (locked-спека).** Следуем `settings-root.md` (источник истины, Принцип II): Logout → 1.1 Splash после полной очистки. Упоминание Login в десктоп-корпусе трактуется как дрейф (как сделали с `login.md` в M2); `settings-root.md` не меняется.
- Q: Отрисовка QR на 7.1 (Show QR) — roadmap допускает «`qr_flutter`/заглушка»; в M2 камеру строили без плагина (правило «no new deps»). → A: **Заглушка (без новых зависимостей).** Рендерим нейтральный fake-QR паттерн на brand-fixed светлой поверхности (#FFFFFF `qr-surface`/`qr-ink`), реальное кодирование идентификатора — Фаза 2. Согласуется с прецедентом M2 (камера-плейсхолдер) и правилом «no new deps».
- Q: Как центральная `+` шелла открывает Create chat (6.1) на десктопе (FR-022 говорил «на весь экран», но 6.1 на десктопе — модальный `Dialog`)? → A: **Width-adaptive.** `+` открывает 6.1 в его форме по ширине окна: на мобайле — fullscreen push поверх шелла (нижняя панель скрыта), на десктопе — модальный `Dialog` (~460) со scrim над шеллом (как 6.1 в M2 / корпус `07-create`). Шелл вызывает адаптивный вход 6.1, новой логики не добавляет; устранено противоречие с locked-спекой 6.1.
- Q: Раскрывается ли raw-ID в карте идентичности на десктопе (locked-спека `settings-root.md` даёт `Show/Hide`, корпус `02-settings` — «no secret reveal on desktop»)? → A: **На десктопе raw-ID не раскрывается.** Десктоп: всегда маска `••••••••` (нет `Show/Hide`), вместо reveal — inline account-QR в карте, действия `Copy` + `Show QR` (увеличенный центрированный `Dialog`). Мобайл сохраняет `Show/Hide` по locked-спеке. `AppIdentityCardWidget` параметризуется (`revealable`: мобайл=true / десктоп=false; inline-QR: десктоп=true). Согласуется с Принципом I (минимизация раскрытия секрета) и десктоп-корпусом.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Адаптивный шелл (Tab-bar shell, 4.1) (Priority: P1)

Авторизованный пользователь видит каркас приложения: две навигационные цели (`Chats` / `Settings`) и центральное действие создания чата (`+`). Это скелет, в котором рендерятся root-экраны табов; на узком окне — нижняя панель с вырезом и docked `+`, на широком — `NavigationRail` с `+` сверху.

**Why this priority**: Несущий каркас этапа — без него остальные экраны не композируются. Это головной блок «скелета приложения», который хостит 5.1 и 7.1 и вводит адаптивный паттерн bottom-bar ↔ rail и контейнер list-detail.

**Independent Test**: Открыть шелл (4.1) из Галереи на узком и широком окне; убедиться, что узкое окно даёт `BottomAppBar` с вырезом + docked `+` FAB, широкое (≥840) — `NavigationRail` + leading `+`; переключение табов сохраняет состояние каждого таба (скролл/ввод не сбрасываются); `+` открывает реальный экран создания чата (6.1).

**Acceptance Scenarios**:

1. **Given** шелл открыт на узком окне, **When** он показан, **Then** внизу — `BottomAppBar` с круглым вырезом, два таба по краям (иконка + подпись `Chats` / `Settings`, selected — `primary` + заполненная иконка) и центральный docked `+` FAB (`primaryContainer`) в вырезе, видимый на обоих табах; body = активный root-экран таба.
2. **Given** шелл открыт на широком окне (≥840), **When** он показан, **Then** слева — `NavigationRail` с двумя целями и leading `+` FAB; body занимает оставшуюся ширину; адаптив выбран по ширине окна (`LayoutBuilder`/`railBreakpoint`), а не по платформе.
3. **Given** активен таб Chats, **When** пользователь переключается на Settings и обратно, **Then** состояние каждого таба сохранено (`IndexedStack`: позиция скролла и ввод не сбрасываются); переключение — с короткой fade (`tabFade` ≤150 мс).
4. **Given** любой таб активен, **When** пользователь нажимает `+` (tooltip `New chat`), **Then** реальный 6.1 (M2) открывается в width-adaptive форме — мобайл: fullscreen push поверх шелла с скрытой нижней панелью; десктоп: модальный `Dialog` (~460) со scrim над шеллом; возврат/закрытие — на исходный таб.
5. **Given** повторный тап по активному табу, **When** активен Chats, **Then** список чатов скроллится в начало; **When** активен Settings, **Then** no-op.
6. **Given** системный back на root-табе, **When** активен не Chats (Settings) → переключение на Chats; **When** активен Chats → сворачивание приложения (`SystemNavigator.pop`, в standalone-превью — заглушено/возврат в Галерею); на pushed-экране back обрабатывается самим экраном.

---

### User Story 2 — Корень настроек (Settings root, 7.1) (Priority: P2)

Пользователь на табе `Settings` видит карту идентичности (имя + идентификатор), плоский список разделов настроек и действие Logout. Имя редактируется inline; идентификатор по умолчанию замаскирован, его можно показать/скопировать/показать QR; Logout запрашивает подтверждение и ведёт на Splash.

**Why this priority**: Композирует таб Settings и вводит карту идентичности (`AppIdentityCardWidget`), settings-nav-строки и logout-диалог. Все целевые подэкраны (7.2–7.7) уже построены (M1), поэтому переходы реальны.

**Independent Test**: Открыть 7.1 (внутри шелла и standalone из Галереи) на узком и широком окне; убедиться, что блок имени переходит в inline-edit с charset+uniqueness-валидацией (как 2.3), `Your ID` маскируется `••••••••` с действиями Copy · Show QR (+ Show/Hide только на мобайле), строки настроек открывают реальные 7.2–7.7, а Logout (после подтверждения) ведёт на реальный Splash (1.1).

**Acceptance Scenarios**:

1. **Given** 7.1 открыт на мобайле, **When** он показан, **Then** `Scaffold` (внутри шелла) с `AppBar` `Settings`, прокручиваемый `ListView`: filled `Card` идентичности (блок `Name` + блок `Your ID`) и плоский список `ListTile` — `Notifications` / `Appearance` / `Language` / `Terms` / `About` + `Log out` (последний в `ColorScheme.error`).
2. **Given** блок имени, **When** пользователь тапает имя / pencil, **Then** строка превращается в inline `TextField` с фокусом, counter `N/32`, suffix-спиннером проверки занятости и charset-валидацией (`[A-Za-z0-9._-]`, case-sensitive uniqueness по мок-набору — как в 2.3); Save по Enter/Done/blur при валидном; invalid/taken — остаёмся в edit с `errorText`; пустое поле → имя не меняется; Cancel/back — прежнее значение.
3. **Given** на **мобайле** блок идентификатора замаскирован (`••••••••`, 8 точек), **When** пользователь тапает `Show`, **Then** показывается raw-идентификатор (monospace, wrap по строкам), action-row остаётся под текстом; `Hide` возвращает маску; `Copy` копирует raw-ID + snackbar `Copied to clipboard`. (На десктопе `Show/Hide` отсутствует — см. сценарий 7 и FR-037.)
4. **Given** пользователь тапает `Show QR`, **When** на мобайле, **Then** открывается modal bottom sheet (drag-handle, заголовок `Your ID QR`, нейтральный fake-QR на **brand-fixed светлой поверхности** #FFFFFF, quiet-zone, `Close`; raw-ID текстом не показывается; wrap-height); **When** на десктопе, **Then** тот же QR — в центрированном `Dialog`. Реальное QR-кодирование заглушено.
5. **Given** пользователь тапает `Log out`, **When** показан `AlertDialog` (`Log out?` / `Your ID and local data will be removed from this device.` / `Log out` · `Cancel`) и подтверждает, **Then** Logout-loading (кнопка диалога disabled + спиннер, диалог модален), затем переход на реальный **1.1 Splash** после (заглушенной) очистки.
6. **Given** строка раздела, **When** пользователь тапает её на мобайле, **Then** реальный подэкран 7.2–7.7 (M1) открывается push поверх шелла на весь экран с скрытой нижней панелью.
7. **Given** широкое окно (десктоп), **When** 7.1 показан, **Then** list-detail (корпус `02-settings`): `NavigationRail` + settings-menu-pane (≈340) + detail-pane (≤680); выбор пункта меню подсвечивает его (`secondaryContainer`) и **меняет detail-pane без push**, переиспользуя контент M1-подэкранов; в карте идентичности raw-ID **не раскрывается** (нет `Show/Hide`, всегда маска), вместо него — inline account-QR, действия `Copy` + `Show QR`; Logout/Show QR — центрированный `Dialog`.
8. **Given** Initial-loading, **When** идентификатор ещё грузится (заглушка), **Then** в позиции ID — `CircularProgressIndicator`, остальные пункты списка уже доступны. Состояния Inline-error (snackbar/`errorText`) и Fatal (→ 3.1) воспроизводимы debug-переключателем.

---

### User Story 3 — Список чатов (Chats list, 5.1) (Priority: P3)

Пользователь на табе `Chats` видит глобальный список всех чатов (открытое общее пространство), может искать по имени и обновлять список pull-to-refresh. На десктопе — двухпанельный list-detail: список слева, лента справа.

**Why this priority**: Главный рабочий экран и первый носитель адаптивного **list-detail**. P3, потому что лента чата 5.2 (правая панель десктопа и цель тапа на мобайле) ещё не построена (M4) — её контент остаётся плейсхолдером, тогда как механика list-detail строится полностью.

**Independent Test**: Открыть 5.1 (внутри шелла и standalone из Галереи) на узком и широком окне; на узком — `AppBar` (wordmark `NOX`) + постоянная `SearchBar` + список чатов с относительным временем и unread-бейджем; на широком — rail + list-pane 360 + thread-pane; выбор строки подсвечивает её без push; debug-переключателем воспроизвести Initial-loading / Empty / Filled / Searching / Search-empty / Offline / Inline-error / Fatal.

**Acceptance Scenarios**:

1. **Given** 5.1 открыт на мобайле в состоянии Filled, **When** он показан, **Then** `Scaffold` (внутри шелла) с `AppBar` (wordmark `NOX`), постоянной M3 `SearchBar` (placeholder `Search`) под ним и `ListView.builder` (в `RefreshIndicator`) элементов чатов: generated-аватар + имя + превью последнего сообщения (ellipsis) + относительное время (`now`/`5 min`/`2 h`/`Yesterday`/`12 May`) + unread-бейдж (число, роль `primary`, скрыт при 0, cap `99+`).
2. **Given** список пуст, **When** Empty, **Then** иллюстрация + заголовок `No chats yet` + текст `Tap + to create the first one.`; при непустом запросе без совпадений (Search-empty) — `No chats found`.
3. **Given** пользователь вводит запрос в `SearchBar`, **When** ввод обработан, **Then** список фильтруется по имени чата в реальном времени; повторный тап по табу Chats скроллит в начало; long-press — no-op; сортировка фиксирована по времени последнего сообщения.
4. **Given** нет соединения (заглушка/debug), **When** Offline, **Then** постоянный `MaterialBanner` `No connection` сверху (под AppBar/SearchBar), список показывает кэш; при ошибке загрузки (Inline-error) — `MaterialBanner` `Could not load chats. Pull to refresh.`; pull-to-refresh (`RefreshIndicator`) перезапрашивает (заглушка); Fatal → 3.1 (embedded).
5. **Given** широкое окно (десктоп), **When** 5.1 показан, **Then** list-detail (корпус `01-chats`): rail + chat-list-pane (≈360, pane-header + `SearchBar`) + thread-pane; выбор строки подсвечивает её (`secondaryContainer`) и **загружает ленту справа без push**; no-selection → thread-pane placeholder `Select a chat` / `Choose a conversation on the left, or press + to start a new one.`; offline-баннер — в обеих панелях, loading-спиннер — в list-pane, transient snackbar — по центру над thread-pane.
6. **Given** пользователь тапает элемент списка (мобайл) или выбирает строку (десктоп), **When** ленты 5.2 ещё нет (M4), **Then** контент ленты — лёгкий плейсхолдер «лента — в M4» (механика навигации/выбора реальна, контент 5.2 — заглушка, помечена точкой замены).

---

### Edge Cases

- **Шелл (4.1):** pushed-экраны (6.1; Chats-стек 5.2/5.3/5.4; Settings-стек 7.2–7.7) открываются на весь экран без нижней панели; возврат из `+`/6.1 — на исходный таб (шелл запоминает таб открытия). Системный back: не-Chats → Chats, на Chats → свернуть приложение (в standalone-превью семантика «свернуть» заглушена). Десктоп — single-window.
- **Шелл (4.1) — узкое окно десктопа:** узкое окно десктопа получает мобильный лейаут (bottom bar), широкое — rail; `Platform`-проверок для лейаута нет.
- **Settings (7.1) — inline-name-edit:** kill-приложения безопасен (имя `User<random>` уже «назначено»); ответ «занято» может прийти на save (гонка real-time vs save) → остаёмся в edit с `errorText`, фокус не теряем; пустое поле при save → имя не меняется (label нельзя обнулить).
- **Settings (7.1) — десктоп detail-pane:** M1-подэкраны переиспользуются в правой панели **без собственного back/полноэкранного chrome** (свап панели, не push); на мобайле те же подэкраны — push на весь экран поверх шелла.
- **Chats (5.1):** при первой загрузке — centered спиннер (не skeleton); offline показывает кэш, не пустоту; relative-time форматтер устойчив к границам (`now` < 1 мин, `Yesterday`, дата `12 May` для давних); generated-аватар имеет fallback-иконку для не-латиницы/символов.
- **Chats (5.1) — десктоп list-detail без ленты:** правая панель в M3 — плейсхолдер (5.2 = M4); выбор строки и highlight работают, но реального контента ленты нет; точка замены помечена.
- **Все экраны:** компоновка не ломается при большом масштабе текста и при узком/широком окне; debug-контролы воспроизведения состояний доступны только в dev-превью и не являются частью продуктового UI.

## Requirements *(mandatory)*

### Functional Requirements — сквозные

- **FR-001**: Все три экрана M3 (Tab-bar shell 4.1, Settings root 7.1, Chats list 5.1) MUST быть реализованы; соответствующие строки «Галереи экранов» MUST активироваться (перестают быть `Coming soon`).
- **FR-002**: Каждый экран MUST иметь две адаптивные раскладки — мобайл (узкое окно) и десктоп (широкое окно), выбираемые по ширине окна (`LayoutBuilder` по `Constants.railBreakpoint` = 840dp), а не по платформе. Ключевые десктоп-отличия: 4.1 — `NavigationRail` + leading `+` FAB (вместо `BottomAppBar` + docked FAB); 7.1 — list-detail (menu-pane ≈340 + detail-pane ≤680) + QR/Logout как `Dialog` (вместо fullscreen + bottom sheet); 5.1 — list-detail (rail + list-pane 360 + thread-pane) (вместо bottom bar + push).
- **FR-003**: Каждый экран MUST корректно отображаться в светлой и тёмной теме и при переключении темы. M3 вводит **второе** brand-fixed исключение проекта — **светлую поверхность отображения QR** на 7.1 (#FFFFFF `qr-surface`/`qr-ink`, сканируема в обеих темах; источник `design-system.md` §9.10), которая **не** темизируется (первое исключение — тёмный splash 1.1, M1). Всё остальное в M3 темизируется.
- **FR-004**: Вся пользовательская микрокопия MUST быть на английском через `TextConstants`; строковых литералов в виджетах и русского текста в UI быть не должно.
- **FR-005**: Все визуальные состояния каждого экрана, определённые его спекой, MUST быть воспроизводимы на заглушечных данных без бэкенда — через сочетание in-memory мок-набора (список чатов, идентичность, занятые имена) и локальных debug-переключателей (loading/offline/error/fatal, исходы name-edit и logout).
- **FR-006**: Любая бэкенд-зависимость (загрузка/кэш списка чатов, серверная проверка уникальности имени, чтение/очистка идентификатора, QR-кодирование, реальная маршрутизация по флоу) MUST быть заглушена (фейковый результат/no-op) и помечена точкой будущей замены `// TODO(backend):`.
- **FR-007**: Каждый экран MUST быть покрыт автотестами уровня widget и golden (светлая + тёмная темы), по правилам именования/тегов проекта, через харнес `pumpApp`.
- **FR-008**: M3 MUST вживить **реальную композицию** уже построенных экранов (отступление от standalone-правила M1/M2): шелл хостит реальные 5.1 + 7.1 как табы; центральная `+` → реальный 6.1; строки 7.1 → реальные 7.2–7.7; Logout → реальный 1.1 Splash. **Единственная** заглушка-назначение — лента чата 5.2 (этап M4, не построена): тап по чату (мобайл) и thread-pane (десктоп) ведут на лёгкий плейсхолдер, помеченный точкой замены.
- **FR-009**: Этап MUST ввести и переиспользовать несущие блоки скелета без дивергенции: (а) **адаптивный шелл** `TabBarShell` (bottom bar ↔ `NavigationRail`, контейнер list-detail; reuse `AppBottomBarWidget`/`AppCreateFabWidget`); (б) **карту идентичности** `AppIdentityCardWidget` + `AppLogoutDialogWidget` + settings-nav-строку `AppSettingsNavRowWidget`; (в) **форматтер относительного времени** (лестница из `overview.md`). Несколько несогласованных реализаций не допускаются.
- **FR-010**: Галерея экранов MUST давать доступ к каждому экрану: строка 4.1 открывает **живой композированный шелл** (с реальными 5.1 + 7.1 как табами); строки 5.1 и 7.1 дополнительно открывают экран **standalone** (паттерн `routeDemo`, как у root-экранов M2) для изолированной проверки в обеих темах и раскладках.

### Functional Requirements — Tab-bar shell (4.1)

- **FR-020**: Шелл MUST на мобайле выводить `Scaffold` с `BottomAppBar` (круглый вырез `CircularNotchedRectangle`) и центральным docked `FloatingActionButton` (`FloatingActionButtonLocation.centerDocked`); два таба по краям выреза (иконка + подпись `Chats` / `Settings`; selected — `primary` + заполненная иконка, unselected — `onSurfaceVariant` + контурная). На десктопе (≥840) — `NavigationRail` (две цели) с `+` как leading FAB.
- **FR-021**: Body шелла MUST быть активным root-экраном таба (Chats → 5.1, Settings → 7.1) через `IndexedStack` с сохранением состояния каждого таба (скролл/ввод не сбрасываются); переключение — fade `tabFade` ≤150 мс.
- **FR-022**: Центральная `+` (tooltip `New chat`) MUST быть видима на обоих табах и открывать реальный 6.1 в его **width-adaptive** форме: на мобайле — fullscreen push поверх шелла (нижняя панель скрыта), на десктопе — модальный `Dialog` (~460) со scrim над шеллом (как 6.1 в M2 / корпус `07-create`), а не полноэкранно; возврат/закрытие — на исходный таб. Шелл вызывает адаптивный вход 6.1 и не дублирует его логику.
- **FR-023**: Повторный тап по активному табу MUST: для Chats — скроллить список в начало; для Settings — no-op.
- **FR-024**: Системный back на root-табе MUST: если активен не Chats (Settings) → переключить на Chats; если активен Chats → свернуть приложение (`SystemNavigator.pop`, в standalone-превью заглушено как точка замены `// TODO(backend):`). На pushed-экране back обрабатывается самим экраном.
- **FR-025**: Pushed-экраны Chats-стека (5.2/5.3/5.4) и Settings-стека (7.2–7.7) MUST открываться на весь экран поверх шелла **без** нижней панели/rail-контекста. Исключение — 6.1, которое на десктопе открывается модальным `Dialog` со scrim (FR-022), а не полноэкранно.
- **FR-026**: Шелл MUST быть чисто презентационным (`StatefulWidget`, индекс таба + `IndexedStack`, без BLoC — карв-аут блюпринта 05 §5.1) и сверен с верификационным Feature-001 `AppShell`, заменяя его как живой шелл; расхождение с блюпринтом чинится в этом же change-set.

### Functional Requirements — Settings root (7.1)

- **FR-030**: 7.1 MUST на мобайле выводить `Scaffold` (внутри шелла) с `AppBar` `Settings` и прокручиваемым `ListView`: filled `Card` идентичности + плоский список `ListTile` (`Notifications` / `Appearance` / `Language` / `Terms` / `About`) + `Log out` (последний пункт, `ColorScheme.error`). Group-заголовков нет.
- **FR-031**: Карта идентичности MUST содержать блок имени (label `Name` + текущее имя + edit-pencil) и блок идентификатора (label `Your ID` + маска `••••••••` фиксированной длины 8 + action-row). Состав action-row зависит от раскладки: **мобайл** — `Show/Hide` · `Copy` · `Show QR`; **десктоп** — `Copy` · `Show QR` (без `Show/Hide` — raw-ID на десктопе не раскрывается, FR-037).
- **FR-032**: Тап на имя / pencil MUST переводить блок имени в inline `TextField` с фокусом, counter `N/32`, suffix-спиннером проверки занятости и **клиентской charset-валидацией** (`[A-Za-z0-9._-]`) + **case-sensitive** uniqueness против мок-набора (как 2.3). Save — по Enter/Done/blur при валидном; invalid/taken — остаёмся в edit с `errorText` (фокус не теряем); пустое поле при save → имя не меняется; Cancel/системный back → прежнее значение.
- **FR-033**: На **мобайле** `Show/Hide` MUST переключать маску `••••••••` ↔ raw-идентификатор (monospace, wrap по строкам, action-row под текстом); на **десктопе** `Show/Hide` отсутствует и raw-ID не раскрывается (всегда маска, FR-037). `Copy` MUST копировать raw-ID в буфер + snackbar `Copied to clipboard` (обе раскладки).
- **FR-034**: `Show QR` MUST открывать QR-поверхность: на мобайле — modal bottom sheet (drag-handle, заголовок `Your ID QR`, `Close`, wrap-height), на десктопе — центрированный `Dialog`. QR рендерится как **нейтральный fake-QR паттерн на brand-fixed светлой поверхности** (#FFFFFF, сканируема в обеих темах); raw-ID текстом не показывается. Реальное QR-кодирование идентификатора заглушено (`// TODO(backend):`, без зависимости `qr_flutter`) — Фаза 2.
- **FR-035**: `Log out` MUST открывать `AlertDialog` (title `Log out?`, message `Your ID and local data will be removed from this device.`, confirm `Log out` / cancel `Cancel`). На confirm — Logout-loading (кнопка диалога disabled + `CircularProgressIndicator`, диалог модален и не закрывается до завершения), затем переход на реальный **1.1 Splash** после (заглушенной) полной очистки локальных данных. Целевой экран — 1.1 Splash по locked-спеке `settings-root.md` (упоминание Login в десктоп-корпусе — дрейф).
- **FR-036**: Тап на строку раздела MUST на мобайле push реальный подэкран 7.2–7.7 (M1) на весь экран поверх шелла; на десктопе — **сменить detail-pane без push**, переиспользуя контент того же подэкрана.
- **FR-037**: На десктопе 7.1 MUST выводиться как list-detail (корпус `02-settings`): `NavigationRail` + settings-menu-pane (≈340) + detail-pane (≤680); выбор пункта меню подсвечивает его (`secondaryContainer`) и меняет detail-pane без push. **По умолчанию (до выбора пункта)** detail-pane показывает блок идентичности (account) — дефолтное состояние десктоп-корпуса `02-settings`. Карта идентичности на десктопе: raw-ID **не раскрывается** (всегда `••••••••`, нет `Show/Hide`); вместо reveal в карте показывается **inline account-QR** (на brand-fixed светлой поверхности); действия — `Copy` + `Show QR` (увеличенный центрированный `Dialog`); editing имени → inline-поле; Logout — центрированный `Dialog`. (Privacy: согласуется с Принципом I — минимизация раскрытия секрета.)
- **FR-038**: 7.1 MUST воспроизводить состояния Initial-loading (`CircularProgressIndicator` в позиции ID, остальной список доступен) / Loaded / Name-editing / QR-overlay / Logout-confirm / Logout-loading / Inline-error (snackbar или `errorText`) / Fatal → 3.1; воспроизводимы мок-набором + debug-переключателем.
- **FR-039**: 7.1 MUST ввести `AppIdentityCardWidget` (параметризуется по раскладке: `revealable` — мобайл=true / десктоп=false; inline account-QR — десктоп=true, FR-037), `AppLogoutDialogWidget`, `AppSettingsNavRowWidget` и `SettingsRootBloc` (Freezed value-state: идентичность name+masked/raw ID, состояние name-edit/availability, loading/error). Reuse M1-блоков (`AppSettingsSwitchRowWidget`, `AppInfoBannerWidget`, `AppDetailScaffoldWidget`, `AppThemeOptionWidget`, `AppVersionTextWidget`, `TermsBody`) для контента detail-pane. Значения идентичности (`User<random>`, raw-ID) — мок/заглушка.

### Functional Requirements — Chats list (5.1)

- **FR-050**: 5.1 MUST на мобайле выводить `Scaffold` (внутри шелла) с `AppBar` (wordmark `NOX`), постоянной M3 `SearchBar` (placeholder `Search`) под ним и `ListView.builder` элементов чатов в `RefreshIndicator`. Элемент (reuse `AppChatItemWidget`): generated-аватар + имя + превью последнего сообщения (ellipsis) + относительное время + unread-бейдж (число, роль `ColorScheme.primary`, скрыт при 0, cap `99+`).
- **FR-051**: 5.1 MUST ввести **форматтер относительного времени** по лестнице `overview.md` (`now` / `5 min` / `2 h` / `Yesterday` / `12 May`); форматтер переиспользуется 5.3/5.4 (M4). (Текущий `DateFormatter` имеет только `short`/`time` — относительный режим добавляется.)
- **FR-052**: Ввод в `SearchBar` MUST фильтровать список по имени чата в реальном времени; при непустом запросе без совпадений (Search-empty) — `No chats found`. Сортировка фиксирована по времени последнего сообщения (переключателя нет). Long-press на элементе — no-op.
- **FR-053**: 5.1 MUST воспроизводить состояния Initial-loading (centered `CircularProgressIndicator`) / Empty (иллюстрация + `No chats yet` / `Tap + to create the first one.`) / Filled / Searching / Search-empty / Offline (постоянный `MaterialBanner` `No connection` сверху, список из кэша) / Inline-error (`MaterialBanner` `Could not load chats. Pull to refresh.`) / Fatal → 3.1 (embedded); воспроизводимы мок-набором + debug-переключателем.
- **FR-054**: Pull-to-refresh (`RefreshIndicator`) MUST перезапрашивать актуальное состояние (заглушка); повторный тап по табу Chats скроллит список в начало.
- **FR-055**: Тап по элементу (мобайл) MUST вести на лёгкий плейсхолдер ленты 5.2 (этап M4, не построена), помеченный точкой замены `// TODO(M4):` / `// TODO(backend):`.
- **FR-056**: На десктопе 5.1 MUST выводиться как list-detail (корпус `01-chats`): `NavigationRail` + chat-list-pane (≈360, pane-header + `SearchBar`) + thread-pane. Выбор строки подсвечивает её (`secondaryContainer`) и **загружает ленту справа без push**; no-selection → thread-pane placeholder `Select a chat` / `Choose a conversation on the left, or press + to start a new one.`; **контент ленты = лёгкий плейсхолдер «лента — в M4»** (реальная 5.2 — этап M4). Offline-баннер — в обеих панелях, loading-спиннер — в list-pane, transient snackbar — по центру над thread-pane.
- **FR-057**: 5.1 MUST ввести `ChatsListBloc` поверх **network-only мок-репозитория чатов** — carve-out по блюпринту (открытый список чатов — первая реальная network-only фича), построенный как verification-only Item-слайс: `ChatModel` (domain) + мок-`GetChatsApi` (синтезирует мок-данные) + `ChatRepository`/`Impl` через DI, возвращающий `RepositoryResult`, с `PagingState`-в-bloc. BLoC держит список чатов, поисковый запрос, loading/offline/error и (для десктопа) выбранный чат для list-detail. **Мок-данные, без реального сервера**; реальный транспорт/кэш заглушён и помечен `// TODO(backend):`.
- **FR-058**: 5.1 MUST переиспользовать готовые виджеты UI-kit: `AppChatItemWidget` (строка чата + unread-бейдж), `AppAvatarWidget` (generated-аватар), `AppSearchBarWidget`, state-виджеты (`AppEmptyContentWidget`/`AppProgressWidget`/`AppErrorWidget`) и feedback-хелперы (`showAppBanner` офлайн-баннер, `showAppSnackBar`).

### Key Entities

- **Screen entry (Галерея экранов)**: запись Галереи — идентификатор (`4.1`/`5.1`/`7.1`), раздел (`Shell` / `Chats` / `Settings`), наличие двух раскладок, способ открытия (живой шелл для 4.1; standalone `routeDemo` для 5.1/7.1).
- **TabBarShell (адаптивный шелл)**: контейнер скелета — две навигационные цели (Chats / Settings) + действие `+`; индекс активного таба; `IndexedStack` (сохранение состояния); адаптив bottom bar ↔ `NavigationRail`; контейнер list-detail для десктопа.
- **Identity (мок)**: публичное имя (label, ≤32, charset `[A-Za-z0-9._-]`, уникальное case-sensitive, default `User<random>`) + технический идентификатор (маска `••••••••` 8 точек / raw monospace); значения — заглушка, не хранятся.
- **Settings section row**: пункт настроек (`Notifications`/`Appearance`/`Language`/`Terms`/`About`) → реальный подэкран 7.2–7.7; на десктопе — свап detail-pane.
- **Chat (мок)**: id, имя (≤64, charset не ограничен, уникальное), превью последнего сообщения, время последнего сообщения (относительное), unread-count (от последнего открытия устройством; never-opened — без бейджа; cap `99+`), generated-аватар (инициалы + хеш-цвет).
- **Availability check (мок)**: статус Checking / Available / Taken на основе фиксированного мок-набора занятых имён (для inline-edit имени на 7.1).
- **Logout outcome (мок)**: подтверждение → (заглушенная) полная очистка локальных данных → переход на 1.1 Splash.
- **QR display surface (brand-fixed)**: светлая поверхность (#FFFFFF) с нейтральным fake-QR; реальное кодирование идентификатора — Фаза 2.
- **Selected chat (десктоп list-detail)**: состояние выбора строки (highlight без push); контент ленты справа — плейсхолдер (5.2 = M4).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Все 3 экрана M3 доступны из Галереи (4.1 — живой шелл; 5.1 и 7.1 — также standalone) и отображаются без ошибок рендеринга в обеих темах и в обеих раскладках (узкое и широкое окно).
- **SC-002**: Для каждого экрана 100% состояний, определённых его спекой, демонстрируемы на заглушечных данных (мок-набор + debug-переключатель).
- **SC-003**: Адаптивный шелл переключает `BottomAppBar`+docked-FAB ↔ `NavigationRail`+leading-FAB по ширине окна на брейкпоинте 840dp; состояние каждого таба сохраняется при переключении (`IndexedStack`).
- **SC-004**: Несущие блоки скелета (`TabBarShell`, `AppIdentityCardWidget`, `AppLogoutDialogWidget`, `AppSettingsNavRowWidget`, форматтер относительного времени) введены один раз и переиспользуются без дублирующих несогласованных реализаций; верификационный Feature-001 `AppShell` сверен/заменён.
- **SC-005**: Реальная композиция работает: из шелла центральная `+` открывает реальный 6.1, строки 7.1 открывают реальные 7.2–7.7, Logout (после подтверждения) ведёт на реальный 1.1 Splash; единственная заглушка-назначение — лента 5.2 (плейсхолдер).
- **SC-006**: Десктоп-list-detail работает: на 5.1 выбор строки подсвечивает её без push и меняет thread-pane (плейсхолдер ленты), no-selection показывает placeholder; на 7.1 выбор пункта меню меняет detail-pane без push.
- **SC-007**: Светлая поверхность отображения QR (7.1) — brand-fixed (#FFFFFF) в обеих темах; всё остальное в M3 темизируется light/dark.
- **SC-008**: 100% пользовательской микрокопии — английская; 0 строк русского текста в UI; каждый экран покрыт widget- и golden-тестами (светлая + тёмная), и проектный гейт качества (`make gate`) проходит зелёным.

## Assumptions

- Бэкенд, транспорт и протокол не выбраны (Конституция, тех-контекст) — поэтому все серверные зависимости (загрузка/кэш списка чатов, проверка уникальности имени, чтение/очистка идентификатора, QR-кодирование, реальная маршрутизация) заглушены и помечены точками будущей замены.
- **M3 вживляет реальную композицию** построенных экранов (отступление от standalone-правила M1/M2): шелл хостит реальные 5.1 + 7.1; `+` → реальный 6.1; строки 7.1 → реальные 7.2–7.7; Logout → реальный 1.1 Splash (решено в Clarifications / FR-008).
- **Лента чата 5.2 (этап M4, не построена)** — единственная заглушка-назначение: тап по чату (мобайл) и thread-pane (десктоп) ведут на лёгкий плейсхолдер; механика навигации/выбора и list-detail строится полностью сейчас (решено в Clarifications / FR-056).
- **Logout → 1.1 Splash** по locked-спеке `settings-root.md` (источник истины, Принцип II); упоминание Login в десктоп-корпусе `02-settings` трактуется как дрейф, `settings-root.md` не меняется (roadmap Q4 — решено).
- **QR-рендер заглушён** (без зависимости `qr_flutter`): нейтральный fake-QR на brand-fixed светлой поверхности; реальное кодирование — Фаза 2 (решено в Clarifications / FR-034; roadmap §6 «qr_flutter/заглушка» → заглушка).
- Шелл — чисто презентационный `StatefulWidget` без BLoC (карв-аут блюпринта 05 §5.1, как `HomePage`/Feature-001 `AppShell`); продуктовые Freezed-BLoC'и этапа — `SettingsRootBloc` (7.1) и `ChatsListBloc` (5.1), с async-логикой формы/загрузки (default 05 §5.1) на заглушечных репозиториях.
- M1-подэкраны (7.2–7.7) переиспользуются в desktop detail-pane 7.1 — может потребоваться лёгкий embedded/pane-режим (без собственного back/полноэкранного chrome); на мобайле они push'атся на весь экран поверх шелла. Десктоп-трактовка подэкранов уже выведена в M1 (width-cap панели) — roadmap Q6.
- Форматтер относительного времени вводится в 5.1 (текущий `DateFormatter` — только `short`/`time`); переиспользуется 5.3/5.4 (M4).
- Светлая поверхность отображения QR (7.1) — **второе** brand-fixed исключение проекта (первое — тёмный splash 1.1, M1); источник `design-system.md` §9.10.
- Каждый tab-root-экран (5.1, 7.1) доступен и внутри шелла (реально), и standalone из Галереи (`routeDemo` с preview-back-аффордансом), зеркаля паттерн `routeDemo` из M2 (root-экраны 2.1/2.3).
- Дизайн-система, UI-kit (`AppBottomBarWidget`, `AppCreateFabWidget`, `AppChatItemWidget`, `AppAvatarWidget`, `AppSearchBarWidget`, state-виджеты) и feedback-хелперы (`showAppSnackBar`/`showAppBanner`) готовы (Feature-003 / M1) и используются как есть; новые блоки M3 вводятся в рамках этой фичи.
- Десктоп-корпус присутствует для 5.1 (`01-chats`) и 7.1 (`02-settings`) и используется как авторитетный desktop-референс наряду с locked-спеками; шелл 4.1 десктоп-трактуется через `01-chats`/`02-settings` (rail) и сверяется с Feature-001 `AppShell`.

## Out of Scope

- **Лента чата 5.2** (контент thread-pane десктопа и цель тапа на мобайле) — этап M4; в M3 — плейсхолдер.
- Реальная авторизация, чтение/хранение/очистка идентификатора, серверная проверка уникальности имени, реальный список чатов (транспорт/кэш), реальное создание чата, реальное QR-кодирование.
- Продуктовый навигационный флоу (`1.1 → 2.1↔2.2 → 2.3 → 4.1`) и замена Галереи экранов реальной навигацией; реальная семантика «свернуть приложение» (`SystemNavigator.pop`).
- Слой локализации (l10n) и персистентность (имя, настройки, выбранный таб/чат) между перезапусками.
- Реальное определение офлайна/соединения (в M3 — заглушка/debug-переключатель).
- Экраны M4 (5.2 лента, 5.3 file view, 5.4 chat card) и Фаза-2-плагины (`qr_flutter`, и пр.).
- Любая backend-интеграция.
