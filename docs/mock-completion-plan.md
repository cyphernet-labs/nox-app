# NOX — план доводки до полностью рабочего приложения на моках (трекер)

> **Живой трекинг-документ.** Идём по нему step-by-step, берём по одной задаче из §2. Цель: приложение полностью работает на моках — реальная локальная **Sembast**-БД копит чаты/сообщения (переживают перезапуск), вся бизнес-логика настоящая, навигация и рефреш данных корректны на **мобилке И десктопе**, приложение подготовлено к будущей интеграции бэкенда через **локализованный seam** (меняется только сетевой слой). API сейчас — мок; реальный транспорт/сервер (§4 роадмапа, блюпринты 04/14/15/16) **не начинаем**.
>
> Основано на мультиагентном ревью кода `develop`. Составлен: 2026-07-24.

## 0. Как пользоваться

- **Статусы:** `☐ TODO` · `◐ IN PROGRESS` · `☑ DONE` · `⊘ WONTFIX/deferred`.
- **Берём по одной задаче** из трекера §2 (по ID). Крупные срезы (помечены **SpecKit**) ведём через Spec Kit (specify→clarify→plan→tasks→implement), ветка мёржится в `develop` **без пуша**. Мелкие (**точечно**) — обычным коммитом.
- Отмечаем прогресс прямо здесь: меняем статус в таблице §2 и, при желании, дописываем дату/коммит.
- Детали каждой задачи — в разделах §3 (навигация), §4 (рефреш), §5 (репозитории/seam).

## 1. Оценка состояния (что уже реально работает)

Ядро — рабочий продукт на моках, не каркас:
- **Чаты/сообщения** — cache-first на настоящей Sembast-БД (`ChatDao`/`MessageDao`): сеются один раз, дальше список/поиск/пагинация/отправка идут из БД и переживают перезапуск. `createChat`/`sendMessage` персистятся.
- **Оптимистичная отправка** настоящая (`ChatThreadBloc`): `pending→sent/error`, retry, офлайн-очередь.
- **Онбординг→шелл спина** (`AppRoot` двухфазный route-swap), сессия/настройки/тема/язык/уведомления **персистятся** (012), **l10n полный** (EN+UK, живое переключение).
- **Seam чист по форме** (`RepositoryResult<T>`, `BaseRepositoryHelper`, маппер/DTO разделены).

Гэпы — не отсутствующий плумбинг, а: **(N)** навигация/переходы (создание чата ведёт в заглушку, двойная навигация), **(R)** рефреш (список одноразовый вместо `watch`), **(D)** целостность (logout не чистит БД, unread, идентичность), **(S)** seam не абстрагирован, **(F/E)** мелкие флоу и хвост DoD/доков.

---

## 2. Трекер задач

Приоритет: 🔴 blocker · 🟠 high · 🟡 medium · 🔵 low. Effort: S/M/L.

### Фаза N — навигация и переходы (mobile + desktop)
| ID | Задача | Приор. | Eff. | Режим | Статус |
|----|--------|:---:|:--:|:---:|:---:|
| N1 | Создание чата: убрать тупик `RoutePlaceholderPage`; на `navSuccess` закрыть Create и открыть тред созданного чата (mobile push / desktop select), блок эмитит созданный `ChatModel`/id (§3d) | 🟠 | M | точечно | ☑ |
| N2 | Список чатов рефрешится после создания (await create → `loadChats(reset)` или `watchChats`; сейчас `push` без `.then`) — связано с R1 (§3d, §4) | 🟠 | M | точечно | ☑ |
| N3 | Убрать двойную навигацию онбординга: `Login`/`SetUsername` не пушат `TabBarShell` сами, а двигают спину (`AppRoot` делает единственный swap) (§3e) | 🟡 | M | точечно | ☐ |
| N4 | (опц.) Вход в `Settings/Account` с мобилки (на десктопе есть аватар в rail; на мобилке affordance нет) (§3c) | 🔵 | S | точечно | ☐ |
| N5 | Десктопный `CreateChatPage` — настоящий `showDialog`, а не pushed-route (`// TODO(M3)`) (§3f) | 🔵 | S/M | точечно | ☐ |

### Фаза R — рефреш данных / реактивность
| ID | Задача | Приор. | Eff. | Режим | Статус |
|----|--------|:---:|:--:|:---:|:---:|
| R1 | Список чатов → `watchChats()` реактивно (новый чат и новое сообщение отражаются живо: превью/порядок/unread) (§4) | 🟠 | M | **SpecKit** | ☐ |
| R2 | `sendMessage` обновляет строку чата (`lastMessagePreview`/`lastMessageAt`/порядок) — часть среза R1 (§4) | 🟠 | S | **SpecKit** | ☐ |
| R3 | Тред → `watchMessages(chatId)` реактивно (живой приём; своя отправка уже оптимистична) (§4) | 🟡 | M | **SpecKit** | ☐ |
| R4 | Аватар в шелле + Settings живо обновляются после переименования (broadcast label) — связано с D3 (§4) | 🟡 | S/M | **SpecKit** | ☐ |
| R5 | Chat card (5.4) — файлы реактивно/из персистентных вложений — связано с E3 (§4) | 🔵 | M | точечно | ☐ |

### Фаза D — целостность данных и бизнес-правила
| ID | Задача | Приор. | Eff. | Режим | Статус |
|----|--------|:---:|:--:|:---:|:---:|
| D1 | **Logout чистит чат/сообщения из Sembast** (`clean()` есть, но не вызывается) — утечка между identity (§5) | 🔴 | S/M | точечно | ☑ |
| D2 | Unread-count: инкремент на новое сообщение, сброс при открытии чата (§4) | 🟠 | M | **SpecKit** | ☐ |
| D3 | Единая идентичность: один источник (session label) кормит автора своих сообщений + Settings; переименование персистится в сессию (сейчас `_onNameSubmitted` — no-op) (§4, §5) | 🟠 | M | **SpecKit** | ☐ |
| D4 | Уникальность имени чата — против накапливающейся БД, а не замороженного мок-сета | 🟡 | S/M | точечно | ☐ |
| D5 | Новый чат получает системную строку `Chat created by {label}` | 🟡 | S | точечно | ☐ |

### Фаза S — систематизация репозиториев и seam под интеграцию (API остаётся мок)
| ID | Задача | Приор. | Eff. | Режим | Статус |
|----|--------|:---:|:--:|:---:|:---:|
| S1 | Интерфейсы `*RemoteDataSource` на фичу; моки реализуют их; репо зависят от интерфейса (P1) (§5.3) | 🟠 | M | **SpecKit** | ☐ |
| S2 | DI-флип по `Environment`: mock↔real = конфиг, а не переписывание (P5) — после S1 (§5.3) | 🟡 | S/M | **SpecKit** | ☐ |
| S3 | Маппинг HTTP-кодов → `RepositoryException` в `BaseRepositoryHelper` (энум-члены есть, но не производятся) (P3) (§5.3) | 🟡 | S | точечно | ☑ |
| S4 | Провести live chat/message через `ResponseEntity` + `EntityConverter` (wire-DTO; наполнить пустой `EntityConverter`), как Item-harness (P2) (§5.3) | 🟡 | L | **SpecKit** | ☐ |
| S5 | Auth/token + apiUrl seam: `AppConfig.apiUrl`, `getUserAuthIdToken`, `ApiClient` interceptor, `401→logout(forced)` (P4) (§5.3) | 🟡 | M | **SpecKit** | ☐ |

### Фаза F — мелкие флоу и заглушки
| ID | Задача | Приор. | Eff. | Режим | Статус |
|----|--------|:---:|:--:|:---:|:---:|
| F1 | Реальный file picker для вложений (сейчас `_onAttachmentPicked` — хардкод `photo.jpg`) | 🟡 | S/M | точечно | ☐ |
| F2 | File-view (5.3) Save — мок-сохранение в локальную папку (сейчас no-op) | 🔵 | S | точечно | ☐ |
| F3 | Достижимость error/empty/offline в реальном флоу (мок-«fault toggle» вне `kDebugMode`) — связано с S3 | 🟡 | M | точечно | ☐ |

### Фаза E — хвост DoD и доки
| ID | Задача | Приор. | Eff. | Режим | Статус |
|----|--------|:---:|:--:|:---:|:---:|
| E1 | Golden 5.2 (chat thread) — page-mobile + page-desktop | 🟡 | M | точечно | ☐ |
| E2 | Golden 4.1 (собранный tab-bar shell) | 🔵 | M | точечно | ☐ |
| E3 | `getChatFiles` выводить из персистентных вложений `MessageDao` (закрыть T009) | 🔵 | M | точечно | ☐ |
| E4 | Сверка `roadmap-phase2.md` (012/013/l10n/clock сделаны) + удалить stale «no l10n»-комментарии (`LanguagePage`, CLAUDE.md) | 🟡 | S | точечно | ☐ |

**Рекомендуемый порядок:** N1→N2 (ваши примеры — «ведёт непонятно куда» + не рефрешится) → R1/R2 → D1 → D3/R4 → S1/S2/S3 → остальное. Крупные срезы (R1/R2/D2, D3/R4, S1/S2, S4, S5) — через Spec Kit.

---

## 3. Навигация и переходы (карта + дефекты)

Топ-уровень маршрутизирует **не страницы, а `AppRoot`** через спину app-state: `unauthorized→Login`, `registrationPending→SetUsername`, `authorized→TabBarShell`; первый переход — `pushReplacement`, пересечение auth-границы — `pushAndRemoveUntil` (назад через границу нельзя).

**Mobile (narrow, < `Constants.railBreakpoint` 840):** `Splash → Login/QR → SetUsername → TabBarShell` (bottom bar Chats/`+`/Settings). Из шелла: список → `push(ChatThreadPage)`; тред → имя чата `InkWell`→`showChatCard`→`push(ChatCardPage)`; файл→`push(FileViewPage)`; Settings → каждый пункт `push(...)` в под-страницу; Logout → диалог → `authRepository.logout()` → спина возвращает на Login.

**Desktop (wide, ≥840):** `TabBarShell._desktop` = `AppWindowTitlebarWidget` + `Row[AppNavigationRailWidget | Expanded(body)]`. Список чатов — **master-detail** (`AppListDetailWidget`): выбор строки **не пушит**, а через `ChatsListEvent.chatSelected` меняет `selectedChatId` → detail-панель показывает `AppThreadViewWidget`. Chat card → `showRightSideSheet`; file view → центрированный `Dialog`. Settings — тоже master-detail (панель меню + инлайн-тело секции). Аватар внизу rail → переключает на Settings + прыжок в секцию Account.

### Дефекты (по вашим наблюдениям и не только)
- **(N1) Создание чата ведёт в тупик.** `create_chat_page.dart` на `navSuccess` пушит `RoutePlaceholderPage(destinationLabel:'Chat thread (5.2)')` — заглушку, а не тред созданного чата и не возврат в список. При этом чат уже персистится (`create_chat_bloc.dart` → `chatRepository.createChat`). **Надо:** закрыть Create и открыть тред созданного чата (mobile push / desktop select), для чего блок должен эмитить созданный `ChatModel`/id. **M.**
- **(N2) Список не рефрешится после создания.** `_onCreate` (`tab_bar_shell_widget.dart`) = `Navigator.push(CreateChatPage.route())` **без `.then(...)`**, а `ChatsListBloc` грузит `getChats` только на `Initialize` и **не подписан на `watchChats()`** (стрим есть — `chat_repository_impl.dart`). Новый чат невидим до ре-инициализации. **M** (см. R1).
- **(N3) Двойная навигация онбординга.** `login_page.dart` (`navRegistered`) и `set_username_page.dart` (`navSuccess`) сами `push(TabBarShell.route())`, но спина `AppRoot` тоже маршрутизирует в `TabBarShell` при `authorized` через `pushAndRemoveUntil`. Возможен двойной пуш шелла. **Надо:** онбординг двигает спину, `AppRoot` делает единственный swap. **M.**
- **(N4) Вход в Account только на десктопе.** Аватар живёт лишь в `AppNavigationRailWidget`; на мобилке affordance нет (`_onJumpToAccount` — no-op на плоском списке). Не баг, но точки входа на мобилке нет. **S** (если нужна).
- **(N5) Десктопный Create — pushed-route, а не `showDialog`** (`// TODO(M3)`). Косметика/архитектура. **S/M.**
- **Chat card (5.4) — достижим в реальном флоу** (хедер треда `onInfo`→`showChatCard` на обеих ширинах). **Дефекта нет** (ранее ошибочно значился как gallery-only).

---

## 4. Матрица рефреша данных (реактивность)

| Экран/список | Данные | Источник | Обновляется при изменении данных в другом месте? | Гэп |
|---|---|---|---|---|
| Список чатов (`chats_list_bloc`) | превью/время/unread | **одноразовый** `getChats` | **Нет** — игнорит `watchChats()` | новый чат/сообщение не отражаются; порядок/unread устаревают → **R1/R2 [HIGH]** |
| Список после Create | — | `push` без `.then` | **Нет** | устаревает после создания (N2) |
| Тред (`chat_thread_bloc`) | история + `outgoing` | одноразовый `getMessages`; свои — оптимистично | свои — да; входящие/живые — **нет** (нет `watchMessages`) | нет живого приёма → **R3 [MED]** |
| Тред ↔ список | превью/unread | — | **Нет** кросс-сигнала | отправка не двигает строку списка |
| Settings identity/name (`settings_root_bloc`) | name/rawId | одноразовый `readSession`; rename **local-only** (`// TODO(backend)`) | **Нет** — не персистится, не броадкастится | имя теряется между сессиями → **D3** |
| Аватар в шелле | инициалы | одноразовый `readSession` при монтировании | **Нет** | устаревает после rename → **R4** |
| Logout wipe | — | `authRepository.logout()` | спина → Login | чистит ли чат/сообщения из БД — **нет** (D1) |
| Тема / Язык | themeMode / AppLanguage | реактивно (`BlocBuilder` / `ValueListenableBuilder`) | **Да, живо** | OK |
| Chat card (`chat_card_bloc`) | файлы | одноразовый `initialize(chatId)` | **Нет** | нет живого обновления → R5 |

**Одноразовые загрузки, которые должны быть `watch`:** `chats_list_bloc` (`getChats`→`watchChats`), `chat_thread_bloc` (нет входящего стрима), `tab_bar_shell_widget._loadAccountLabel` (одноразовый `readSession`), `settings_root_bloc` (одноразовый + rename local-only), `chat_card_page` (одноразовый `initialize`).

---

## 5. Репозитории: инвентарь + систематизация + seam

### 5.1 Инвентарь
| Интерфейс | Impl | Хранилище | DAO/entity/mapper | Мок-источник | Реактивен | Точка интеграции (что заменит бэкенд) | Fabricated vs persisted |
|---|---|---|---|---|:--:|---|---|
| `ChatRepository` | `ChatRepositoryImpl` | cache-first Sembast | `ChatDao`/`ChatEntity`/`ChatMapper` | `GetChatsApi`, `GetChatFilesApi` | да (`watchChats`) | `_seedIfEmpty→execute`; `getChatFiles→execute` | список/файлы фабрикуются → **персистятся**; `createChat` только локально |
| `MessageRepository` | `MessageRepositoryImpl` | cache-first Sembast | `MessageDao`/`MessageEntity`/`MessageMapper` | `GetMessagesApi`, `SendMessageApi` | DAO умеет `watch`, репо **не отдаёт** | `_seedChatIfEmpty→execute`; `sendMessage→execute`+upsert | история фабрикуется→персистится; send → `srv_<uuid>` sent |
| `ItemRepository` | `ItemRepositoryImpl` | **network-only мок** (без DAO) | `ItemMapper` (`ItemDao`/`ItemEntity` не используются репо) | `GetItemsApi` (единственный через `ResponseEntity<ItemsEntity>`) | нет | `getItems→execute` — **референс DTO↔envelope** | всё фабрикуется, ничего не персистится |
| `SettingsRepository` | impl | local-only prefs | — | — | нет | N/A (локальные преференсы) | персистится |
| `SessionRepository` | impl | local-only secure+prefs | — | — | нет | реальный sign-in заполнит отсюда (токен сюда/в AppConfig) | персистится |
| `AuthRepository` | impl | оркестратор | — | `OnboardingMockData.registeredIds` | нет | `signIn` — **заглушка** (членство в списке id); `logout(forced)` — seam 401 | нет реального auth |
| `AppStateRepository` | impl | in-memory `BehaviorSubject` | — | — | да (`watchAppState`) | N/A (проекция сессии) | derived, не персистится |
| `AppConfigRepository` | impl | in-memory (только flavor) | — | — | нет | **seam apiUrl/token** — сейчас только `flavor` | нет `apiUrl`/токена |
| `LogRepository` | `LoggerLogRepository` | logger | — | — | нет | N/A | — |
| `CameraPermissionService` | impl | платформенное | — | — | нет | N/A (OS-канал) | — |

`AppDatabase` — per-env Sembast-фабрика под DAO (не репо). `ApiClient` — голый `Dio` (таймауты, без baseUrl/interceptor), **никуда не инъектится**.

### 5.2 Seam — текущая реальность
- Моки инъектятся **по конкретному типу** (`GetChatsApi` и т.д.), без интерфейса → «своп на реальный» = правка конструкторов репо, а не смена биндинга.
- Через `ResponseEntity`+`EntityConverter` идёт **только Item**; chat/message возвращают **доменные модели напрямую** (entity-слой у них только под Sembast, не wire-shaped). `EntityConverter` — **пустой реестр**.
- Ошибки: `BaseRepositoryHelper.execute` — только `DioException→internal` и `catch→unknown`; члены `authentication/connection/unauthenticated/notFound` объявлены, но **не производятся** (нет маппинга HTTP-кодов).
- Auth/apiUrl seam **фактически отсутствует**: `ApiClient` без baseUrl/interceptor и не инъектится; в `AppConfig` нет `apiUrl`; нет `getUserAuthIdToken`; нет `401→logout(forced)`.

### 5.3 Систематизация (seam only — реальный бэкенд не строим)
- **P1 (→S1, M):** интерфейсы `ChatRemoteDataSource`/`MessageRemoteDataSource`/`ItemRemoteDataSource`/`ChatFilesRemoteDataSource`; моки их реализуют; репо зависят от интерфейса.
- **P5 (→S2, S/M):** ре-регистрация data-source по `Environment` (mock `[dev,test]` / real `[prod]`) → mock↔real = флип конфига; репо/DAO/маппер не меняются.
- **P3 (→S3, S):** в `BaseRepositoryHelper` маппинг `statusCode` → `RepositoryException` (`401→unauthenticated`, `403→authentication`, `404→notFound`, connection→`connection`).
- **P2 (→S4, L):** wire-DTO для chat/message + `ResponseEntity`-путь как у Item; наполнить `EntityConverter`. Самый крупный сдвиг (сейчас возвращают доменные модели).
- **P4 (→S5, M):** `AppConfig.apiUrl`(+ключ подписи), контракт `AppConfigRepository` (`baseApiUrl`/`getUserAuthIdToken`/`isTestEnvironment`), `ApiClient.initBase()`+auth-interceptor, `401→authRepository.logout(forced:true)`; токен — в secure storage рядом с identifier.

**Целевой итог интеграции:** реализовать N `*RemoteDataSource` + задать `AppConfig.apiUrl` + флипнуть `Environment` — репозитории, DAO, мапперы, `RepositoryResult`/`PageMetadata` и весь UI/BLoC остаются нетронутыми.

---

## 6. Журнал прогресса

_(дописываем строкой на каждую закрытую задачу: `ID — дата — коммит — примечание`)_

- D1 — 2026-07-24 — logout wipes chat/message Sembast on a successful session clear (`AuthRepositoryImpl` gains Chat/Message repo deps; not wiped on a failed clear). Widget logout tests wrapped in `tester.runAsync` (clean() is real DB I/O). Gate green (569).
- N1+N2 — 2026-07-24 — Create chat pops with the created `ChatModel` (no more `RoutePlaceholderPage` dead-end); shell's `_onCreate` awaits it and signals the Chats list (new `openCreated` ValueNotifier) to reload + open the thread (mobile push / desktop select). Gate green (569). NOTE: reload-on-return is the intermediate; full watch-based reactivity is R1.
- 014 — 2026-07-24 — `/speckit-specify` for the reactive-refresh slice (R1+R2+R3+D2). Spec on branch `014-reactive-data-refresh` (`d0eb2e7`); awaiting user for clarify/plan/analyze.
- S3 — 2026-07-24 — `BaseRepositoryHelper` maps DioException by type/status → RepositoryException (401→unauthenticated, 403→authentication, 404→notFound, connection→connection, else internal). Behaviour-neutral on mocks (they never throw); locked by item_repo tests. Gate green (574).
