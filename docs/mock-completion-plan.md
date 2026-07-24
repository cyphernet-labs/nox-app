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
| N3 | ~~Убрать двойную навигацию онбординга~~ — **проверено: НЕ баг** (real-флоу уже spine-driven, page-пуши только в demo-превью, взаимоисключаемо) (§3e) | 🟡 | M | точечно | ☑ |
| N4 | Вход в `Settings/Account` с мобилки — доп. аватар-аффорданс в app-bar списка чатов (тап → `Settings`-таб + прыжок в Account, переиспользует `jumpToAccount` из 011). Ранее ⏸ (Settings-таб уже достижим); **owner-override 2026-07-25: строим явный аффорданс** (принят churn мобильного голдена) (§3c) | 🔵 | S | точечно | ☑ |
| N5 | Десктопный `CreateChatPage` — настоящий `showDialog`, а не pushed-route (`// TODO(M3)`) (§3f) | 🔵 | S/M | точечно | ☑ |

### Фаза R — рефреш данных / реактивность
| ID | Задача | Приор. | Eff. | Режим | Статус |
|----|--------|:---:|:--:|:---:|:---:|
| R1 | Список чатов → `watchChats()` реактивно (новый чат и новое сообщение отражаются живо: превью/порядок/unread) (§4) | 🟠 | M | **SpecKit** | ☑ |
| R2 | `sendMessage` обновляет строку чата (`lastMessagePreview`/`lastMessageAt`/порядок) — часть среза R1 (§4) | 🟠 | S | **SpecKit** | ☑ |
| R3 | Тред → `watchMessages(chatId)` реактивно (живой приём; своя отправка уже оптимистична) (§4) | 🟡 | M | **SpecKit** | ☑ |
| R4 | Аватар в шелле + Settings живо обновляются после переименования (broadcast label) — связано с D3 (§4) | 🟡 | S/M | **SpecKit** | ☑ |
| R5 | Chat card (5.4) — файлы реактивно/из персистентных вложений — связано с E3 (§4) | 🔵 | M | **SpecKit (017)** | ☑ |

### Фаза D — целостность данных и бизнес-правила
| ID | Задача | Приор. | Eff. | Режим | Статус |
|----|--------|:---:|:--:|:---:|:---:|
| D1 | **Logout чистит чат/сообщения из Sembast** (`clean()` есть, но не вызывается) — утечка между identity (§5) | 🔴 | S/M | точечно | ☑ |
| D2 | Unread-count: инкремент на новое сообщение, сброс при открытии чата (§4) | 🟠 | M | **SpecKit** | ☑ |
| D3 | Единая идентичность: один источник (session label) кормит автора своих сообщений + Settings; переименование персистится в сессию (сейчас `_onNameSubmitted` — no-op) (§4, §5) | 🟠 | M | **SpecKit** | ☑ |
| D4 | Уникальность имени чата — против накапливающейся БД, а не замороженного мок-сета | 🟡 | S/M | точечно | ☑ |
| D5 | Новый чат получает системную строку `Chat created by {label}` | 🟡 | S | точечно | ☑ |

### Фаза S — систематизация репозиториев и seam под интеграцию (API остаётся мок)
| ID | Задача | Приор. | Eff. | Режим | Статус |
|----|--------|:---:|:--:|:---:|:---:|
| S1 | Интерфейсы `*RemoteDataSource` на фичу; моки реализуют их; репо зависят от интерфейса (P1) (§5.3) | 🟠 | M | **SpecKit** | ☑ |
| S2 | DI-флип по `Environment`: mock↔real = конфиг, а не переписывание (P5) — после S1 (§5.3) | 🟡 | S/M | **SpecKit** | ☑ |
| S3 | Маппинг HTTP-кодов → `RepositoryException` в `BaseRepositoryHelper` (энум-члены есть, но не производятся) (P3) (§5.3) | 🟡 | S | точечно | ☑ |
| S4 | Провести live chat/message через `ResponseEntity` + `EntityConverter` (wire-DTO; наполнить пустой `EntityConverter`), как Item-harness (P2) (§5.3) | 🟡 | L | **SpecKit (018)** | ☑ |
| S5 | Auth/token + apiUrl seam: `AppConfig.apiUrl`, `getUserAuthIdToken`, `ApiClient` interceptor, `401→logout(forced)` (P4) (§5.3) | 🟡 | M | **SpecKit (019)** | ☑ |

### Фаза F — мелкие флоу и заглушки
| ID | Задача | Приор. | Eff. | Режим | Статус |
|----|--------|:---:|:--:|:---:|:---:|
| F1 | Реальный file picker для вложений (`_onAttachmentPicked` — был хардкод `photo.jpg`, теперь `file_selector` → реальные name/size/type) | 🟡 | S/M | **SpecKit (017)** | ☑ |
| F2 | File-view (5.3) Save — реальное сохранение выбранного файла (копия из локального пути вложения → user-picked папка через `file_selector` `getSaveLocation`), а не только snackbar. Зависит от F4 (picker сохраняет локальный путь). **owner-override 2026-07-25: строим** (§3g) | 🔵 | S | точечно | ☐ |
| F3 | Достижимость error/empty/offline в реальном флоу — **owner-override 2026-07-25: строим достижимое без бэкенда** (empty: пустой поиск / пустой тред / пустой files-view уже реальны; offline: реальный сигнал `connectivity_plus`, не мок-сценарий; error-путь остаётся backend-зависимым — документируем) — связано с S3 (§4) | 🟡 | M | точечно | ☐ |
| F4 | **Инлайн-превью изображений в треде + full-screen просмотр** (owner-запрос 2026-07-25): image-вложения рендерят миниатюру (из локального пути `XFile`, сохранённого F1); прочие типы — type-icon чип как есть; тап по изображению → full-screen вьювер (zoom/закрытие). **РЕВИЗУЕТ locked-решение** `overview.md` «file content previews — type-icon chips only» → теперь image-превью в scope (owner). Требует, чтобы F1-picker сохранял локальный путь во вложении (сейчас только name/size/type). Мультиплатформенно (mobile + desktop). Делать ПОСЛЕДНИМ (§3h) | 🟡 | M | **SpecKit** | ☐ |

### Фаза E — хвост DoD и доки
| ID | Задача | Приор. | Eff. | Режим | Статус |
|----|--------|:---:|:--:|:---:|:---:|
| E1 | Golden 5.2 (chat thread) — page-mobile + page-desktop | 🟡 | M | точечно | ☑ |
| E2 | Golden 4.1 (собранный tab-bar shell) | 🔵 | M | точечно | ☑ |
| E3 | `getChatFiles` выводить из персистентных вложений `MessageDao` (newest-first) — сделано вместе с F1/R5 (реальный picker снял риск демо-регресса); `ChatFilesRemoteDataSource`-seam ретайрен | 🔵 | M | **SpecKit (017)** | ☑ |
| E4 | Сверка `roadmap-phase2.md` (012/013/l10n/clock сделаны) + удалить stale «no l10n»-комментарии (`LanguagePage`, CLAUDE.md) | 🟡 | S | точечно | ☑ |

**Рекомендуемый порядок:** N1→N2 (ваши примеры — «ведёт непонятно куда» + не рефрешится) → R1/R2 → D1 → D3/R4 → S1/S2/S3 → остальное. Крупные срезы (R1/R2/D2, D3/R4, S1/S2, S4, S5) — через Spec Kit.

---

## 3. Навигация и переходы (карта + дефекты)

Топ-уровень маршрутизирует **не страницы, а `AppRoot`** через спину app-state: `unauthorized→Login`, `registrationPending→SetUsername`, `authorized→TabBarShell`; первый переход — `pushReplacement`, пересечение auth-границы — `pushAndRemoveUntil` (назад через границу нельзя).

**Mobile (narrow, < `Constants.railBreakpoint` 840):** `Splash → Login/QR → SetUsername → TabBarShell` (bottom bar Chats/`+`/Settings). Из шелла: список → `push(ChatThreadPage)`; тред → имя чата `InkWell`→`showChatCard`→`push(ChatCardPage)`; файл→`push(FileViewPage)`; Settings → каждый пункт `push(...)` в под-страницу; Logout → диалог → `authRepository.logout()` → спина возвращает на Login.

**Desktop (wide, ≥840):** `TabBarShell._desktop` = `AppWindowTitlebarWidget` + `Row[AppNavigationRailWidget | Expanded(body)]`. Список чатов — **master-detail** (`AppListDetailWidget`): выбор строки **не пушит**, а через `ChatsListEvent.chatSelected` меняет `selectedChatId` → detail-панель показывает `AppThreadViewWidget`. Chat card → `showRightSideSheet`; file view → центрированный `Dialog`. Settings — тоже master-detail (панель меню + инлайн-тело секции). Аватар внизу rail → переключает на Settings + прыжок в секцию Account.

### Дефекты (по вашим наблюдениям и не только)
- **(N1) Создание чата ведёт в тупик.** `create_chat_page.dart` на `navSuccess` пушит `RoutePlaceholderPage(destinationLabel:'Chat thread (5.2)')` — заглушку, а не тред созданного чата и не возврат в список. При этом чат уже персистится (`create_chat_bloc.dart` → `chatRepository.createChat`). **Надо:** закрыть Create и открыть тред созданного чата (mobile push / desktop select), для чего блок должен эмитить созданный `ChatModel`/id. **M.**
- **(N2) Список не рефрешится после создания.** `_onCreate` (`tab_bar_shell_widget.dart`) = `Navigator.push(CreateChatPage.route())` **без `.then(...)`**, а `ChatsListBloc` грузит `getChats` только на `Initialize` и **не подписан на `watchChats()`** (стрим есть — `chat_repository_impl.dart`). Новый чат невидим до ре-инициализации. **M** (см. R1).
- **(N3) Двойная навигация онбординга — ПРОВЕРЕНО (2026-07-25): НЕ воспроизводится.** Уточнённый анализ: `login_bloc`/`set_username_bloc` имеют два **взаимоисключающих** пути. **Реальный** (`signIn`/`completeOnboarding`) двигает спину и эмитит НЕ-nav-статус (`idle`/`valid`) → страница `_onStatus` **не пушит** ничего, единственный swap делает `AppRoot`. **Демо** (`demo=true`, только `kDebugMode`-галерея) эмитит `navRegistered`/`navSuccess` → страница пушит `TabBarShell`/`SetUsername`, но `signIn`/`completeOnboarding` НЕ вызываются, спина НЕ меняется. Т.е. `navRegistered ⟺ demo ⟺ спина-не-двигается`: двойного пуша в шиппинг-флоу нет, а демо-пуши необходимы для превью (спины в галерее нет). «Убрать пуши» сломало бы галерею-превью и чинило бы недостижимый баг. Правки кода не требуется; связь `page→TabBarShell.route()` остаётся только в demo-превью-пути.
- **(N4) Вход в Account только на десктопе.** Аватар живёт лишь в `AppNavigationRailWidget`; на мобилке affordance нет (`_onJumpToAccount` — no-op на плоском списке). Не баг, но точки входа на мобилке нет. **S** (если нужна).
- **(N5) Десктопный Create — ЗАКРЫТО (2026-07-25).** Теперь настоящий `showDialog` (`CreateChatPage.showAsDialog`, `barrierDismissible:false`) поверх живого списка; страница получила `dialog`-режим (`Dialog`-body), shell выбирает showDialog(desktop)/push(mobile). Симулированный `_wide`-scrim удалён.
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
| `ChatRepository` | `ChatRepositoryImpl` | cache-first Sembast | `ChatDao`/`ChatEntity`/`ChatMapper` | `ChatRemoteDataSource` (list); файлы — не мок-источник, а деривация из `MessageDao` (017) | да (`watchChats`) | `_seedIfEmpty→execute`; `getChatFiles→execute`(делегирует `MessageRepository.chatFiles`) | список фабрикуется → **персистится**; файлы = реально отправленные вложения (`ChatFilesRemoteDataSource` ретайрен, 017); `createChat` только локально |
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
- ~~Моки инъектятся **по конкретному типу** (`GetChatsApi` и т.д.), без интерфейса~~ → **закрыто фичей 016 (S1+S2):** репо зависят от интерфейсов `*RemoteDataSource` (`ChatRemoteDataSource`/`MessageRemoteDataSource`/`ItemRemoteDataSource`, `lib/data/remote/datasource/`); моки (`Mock*RemoteDataSource`) делегируют неизменным `*Api`-генераторам и биндятся `@LazySingleton(as: Interface, env:[dev,prod,test])`. «Своп на реальный» = зарегистрировать real-impl на `[prod]` + сузить мок до `[dev,test]` + `make generate` (≤3 шага, репо/DAO/мапперы/UI не трогаются). См. `specs/016-remote-datasource-seam/contracts/di-binding.md`. _(Примечание: `ChatFilesRemoteDataSource` из 016 ретайрен фичей 017 — файлы чата теперь локальная деривация из `MessageDao`, а не сетевой источник.)_
- ~~Через `ResponseEntity`+`EntityConverter` идёт **только Item**; chat/message возвращают **доменные модели напрямую**; `EntityConverter` — **пустой реестр**.~~ → **закрыто S4 (фича 018):** chat-list и message-list на сетевой границе теперь идут через `ResponseEntity<ChatsWireEntity>` / `ResponseEntity<MessagesWireEntity>` (единообразно с Item); генераторы мапят model→wire, репо разворачивают wire→model (`ChatWireMapper`/`MessageWireMapper`, `lib/data/entity/chat/wire/`). `EntityConverter` **наполнен** всеми wire-сущностями (Item + chat + message), `fromJson`/`toJson` их резолвят. Wire-форма — только сетевая граница; локальные Sembast-сущности (форма хранения) не тронуты. Осталось вне S4: `sendMessage` (одиночный POST-эхо) не завёрнут в конверт (отложено). Реальная wire-форма заменит example/TBD при выборе бэкенда.
- Ошибки: `BaseRepositoryHelper.execute` — только `DioException→internal` и `catch→unknown`; члены `authentication/connection/unauthenticated/notFound` объявлены, но **не производятся** (нет маппинга HTTP-кодов).
- ~~Auth/apiUrl seam **фактически отсутствует**: `ApiClient` без baseUrl/interceptor и не инъектится; в `AppConfig` нет `apiUrl`; нет `getUserAuthIdToken`; нет `401→logout(forced)`.~~ → **закрыто S5 (фича 019):** `AppConfig.apiUrl` (nullable TBD), `AppConfigRepository.getUserAuthIdToken()` (читает `auth_id_token` из secure storage, `null` в mock-фазе) + `isTestEnvironment` (env-keyed), `ApiClient.initBase()` (baseUrl из apiUrl + idempotent-установка interceptor'а), `AuthInterceptor` (attach `Bearer` + **401→`authRepository.logout(forced:true)`** с ленивым разрешением `AuthRepository` — DI-cycle-safe). **Инертно** без реального `apiUrl` (0 реальных запросов); `ApiClient` пока не инъектится в data-source'ы. Формы apiUrl/токена/заголовка — example/TBD до выбора бэкенда. Осталось: реальный sign-in, пишущий токен; реальный `apiUrl`; инъекция `ApiClient` в data-source'ы (флип-на-бэкенд).

### 5.3 Систематизация (seam only — реальный бэкенд не строим)
- **P1 (→S1, M):** интерфейсы `ChatRemoteDataSource`/`MessageRemoteDataSource`/`ItemRemoteDataSource`; моки их реализуют; репо зависят от интерфейса. (016 также ввёл `ChatFilesRemoteDataSource`, но 017 его ретайрил — файлы деривируются из `MessageDao`.)
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
- E4 — 2026-07-24 — un-stale l10n claims (CLAUDE.md + LanguagePage/LanguageBody comments) + roadmap reconciliation note. Comment/doc-only, analyze clean.
- **R1+R2+R3+D2 (feature 014) — 2026-07-25 — MERGED into `develop`** (branch `014-reactive-data-refresh`, `--no-ff`). Full Spec Kit flow (specify→clarify→plan→tasks→analyze) + implementation by user story: US1 reactive chats list (watchChats change-signal + `refresh` re-fold of the loaded prefix, `loadedPageCount`, stale-guard, debounce), US2 sendMessage→chat-row (`_touchChatRow`, failed-send-safe), US3 reactive thread (watchMessages + server-id adoption + dedup-by-id, no double bubble), US4 unread (markChatRead on view + debug `simulateIncoming`). Adversarial code-review closed 2 test-coverage gaps (multi-page + search-active refresh). Post-merge gate green (586).
- **E3 (getChatFiles из MessageDao) — 2026-07-25 — ОТЛОЖЕНО (преждевременно, кода не тронуто).** Анализ: 5.4 chat card достигается из треда (5.2 сеет сообщения), так что технически вывод файлов из `MessageDao` реализуем (`MessageRepository.chatFiles(chatId)` seeds+извлекает вложения; можно оставить 016-`ChatFilesRemoteDataSource` или убрать как over-modeling). НО: seeded-тред (`get_messages_api`) содержит ЛИШЬ 1 вложение (`design-spec.pdf`), а текущий фабрикатор `GetChatFilesApi` отдаёт 8 файлов всех типов (pdf/image/sheet/archive/audio/doc/video/text) — богатый showcase 5.4 (grid/list/truncation/type-иконки). Вывод из редких мок-вложений **регрессировал бы демо** (8→1). Корректность (files = реально отправленные вложения) станет ценной ПОСЛЕ **F1** (реальный picker → разнообразные вложения). До тех пор фабрикованный список — уместное mock-фазовое поведение. Помечено ⏸ (зависит от F1).
- **N5 (desktop create-chat modal dialog) — 2026-07-25 — MERGED into `develop`** (branch `n5-desktop-create-dialog`, `--no-ff`, точечно). Десктопный Create теперь открывается настоящим `showDialog` (`CreateChatPage.showAsDialog`, `barrierDismissible:false` как у logout-диалога) — реальный Material `Dialog` поверх ЖИВОГО списка чатов, вместо pushed-route с симулированным scrim-Scaffold (скрывал список). Страница получила `dialog`-режим (`Dialog`-body без full-screen Scaffold); shell `_onCreate({required bool desktop})` выбирает showDialog(rail)/push(FAB). Удалён `// TODO(M3)` `_wide`. Desktop-golden перегенерирован на Dialog-карточку (mobile не тронут). Мультиагентное ревью: 7 findings (barrier-dismiss-race → `barrierDismissible:false`; dead demo-branch; нет end-to-end showAsDialog-теста → добавлены open→Cancel→null / open→Create→ChatModel; desktop shell-ветка не тестировалась → wide-тест рейл→Dialog; golden-scrim-nuance → коммент; stale-трекер) — все закрыты. Гейт зелёный (617+ тестов + 152 голдена).
- **E2 (golden 4.1 tab-bar shell) — 2026-07-25 — MERGED into `develop`** (branch `e2-shell-golden`, `--no-ff`, точечно). Screen-level голдены собранного шелла с дефолтным Chats-табом: page-mobile (360, bottom-bar + docked-FAB) + page-desktop (1280×800, window-titlebar + rail с account-аватаром + list-detail «Select a chat»), light+dark (4 PNG). Bespoke bounded-pump-харнесс (шелл хостит реактивные табы). Фиксирует хром + rail account-аватар (фича 015) + генерируемые chat-аватары/превью/unread. Детерминизм проверен. Тест-онли. Гейт зелёный (617 тестов + **152** голдена).
- **E1 (golden 5.2 chat thread) — 2026-07-25 — MERGED into `develop`** (branch `e1-chat-thread-golden`, `--no-ff`, точечно). Screen-level голдены треда: page-mobile (360) + page-desktop (1280×800, `_wide`-панель), light+dark (4 PNG). Тред реактивный (watchMessages + mock-seed), поэтому стандартный `goldenTest`-харнесс не годится (pumpAndSettle зависает, `settle:false` снимает спиннер) — bespoke-харнесс повторяет `golden.dart` (заморозка часов/шрифтов/поверхности), но settle через bounded-pumps (как реактивные виджет-тесты). Детерминизм проверен повторными прогонами + визуально (own/other пузыри, author-headers, PDF-чип, date-separator, ✓-статусы, композер). Тест-онли, прод-код не тронут. Гейт зелёный (617 тестов + **148** голденов).
- **N3 (onboarding double-nav) — 2026-07-25 — ПРОВЕРЕНО, НЕ баг (no-op, кода не тронуто).** Уточнённый анализ показал: реальный sign-in/onboarding уже spine-driven (эмитит `idle`/`valid`, страница не пушит), а `navRegistered`/`navSuccess`-пуши страниц срабатывают только в `kDebugMode`-demo-превью, где спина не двигается — двойного пуша нет и быть не может. `push(TabBarShell)` в demo-пути необходим (в галерее спины нет). Правки не требуется; §3e и таблица (N3) обновлены с точным анализом. Закрыто без изменения кода.
- **D4 (chat-name uniqueness vs DB) — 2026-07-25 — MERGED into `develop`** (branch `d4-chat-name-uniqueness`, `--no-ff`, точечно). Проверка уникальности имени чата теперь идёт против накапливающейся локальной БД (сеяные + созданные чаты) через новый `ChatRepository.isChatNameTaken(name)` (`getAllSorted` + Dart-`any`, НЕ Sembast-Finder — field_rename:snake gotcha), **case-insensitive** (консистентно с case-insensitive поиском списка). `create_chat_bloc._onAvailabilityRequested`: `taken = DB-проверка || reserved-набор` (`OnboardingMockData.takenChatNames` оставлен как reserved-демо). Seed НЕ в availability-пути (список уже засеял БД до create-chat) — чтобы не тормозить на каждую клавишу. Мультиагентное ревью: 5 LOW-findings (case-mismatch → сделал case-insensitive; DB-путь не покрыт через bloc → добавил bloc-тест; fail-open при read-error + отсутствие data-layer бэкстопа → задокументированы как осознанные mock-трейд-оффы, real uniqueness = backend). Пост-мёрж гейт зелёный (617 тестов + 144 голдена).
- **D5 (create-chat genesis line) — 2026-07-25 — MERGED into `develop`** (branch `d5-create-chat-system-line`, `--no-ff`, точечно — без Spec Kit). Новый чат теперь открывается системной строкой `Chat created by {label}` (автор = session-label, переиспользует identity из 015), а не генерик-мок-историей. `ChatRepositoryImpl.createChat` best-effort сеет genesis-строку через новый `MessageRepository.seedCreatedChat(chatId)` (пишет один `isSystem`-`MessageModel` `${id}_sys`); наличие сообщения → `_seedChatIfEmpty` пропускает генерик-сид. Идемпотентно; guard на `hasData` сессии (не запечатывает fallback-label поверх реальной сессии); seeding не фейлит create (try/catch+log — иначе orphan-чат). Мультиагентное ревью: 4 LOW-findings (non-fatal seeding / hasData-guard / real-session тест) — все закрыты. Пост-мёрж гейт зелёный (613 тестов + 144 голдена).
- **S1+S2 (feature 016) — 2026-07-25 — MERGED into `develop`** (branch `016-remote-datasource-seam`, `--no-ff`). Full Spec Kit flow (specify→plan→tasks→analyze) + implementation. Per-feature abstract `*RemoteDataSource` интерфейсы (`lib/data/remote/datasource/`: Chat/ChatFiles/Message/Item) реализованы `Mock*RemoteDataSource`, которые ДЕЛЕГИРУЮТ неизменным `*Api`-генераторам (их unit-тесты не тронуты → поведение byte-for-byte). Репо зависят от интерфейсов (0 ссылок на конкретные `*Api`); DI биндит `@LazySingleton(as: Interface, env:[dev,prod,test])` — мок покрывает и `prod` (prod-флейвор бутается `Environment.prod`, real-impl ещё нет). **Флип на бэкенд** = документированные ≤3 шага (real на `[prod]` + сузить мок до `[dev,test]` + generate; репо/DAO/мапперы/`RepositoryResult`/UI не трогаются). Swappability доказана `seam_binding_test` (rebinding интерфейса → репо идёт через него, SC-002). Message-интерфейс агрегирует read+send (FR-009). 2 репо-double'а (message failing-send / item error-mapping) перецелены на мок интерфейса. Мультиагентное ревью: 0 подтверждённых замечаний (4 сырых LOW отклонены верификацией). Пост-мёрж гейт зелёный (610 тестов + 144 голдена).
- **D3+R4 (feature 015) — 2026-07-25 — MERGED into `develop`** (branch `015-identity-unification`, `--no-ff`). Full Spec Kit flow (specify→plan→tasks→analyze) + implementation by user story on the local session (no backend): the session is the single identity source. Foundational — pure `resolveIdentity(SessionModel?)→(id,label)` with no-session fallbacks (`IdentityMockData` repurposed to a `fallbackOwnId` sentinel) + a broadcast label channel on `SessionRepository` (`updateLabel`/`watchLabel`). **D3/US1** — chat thread resolves `currentId` from the session, own seed history is reconciled to that identifier at seed time (own-detection identifier-keyed, rename-invariant), new sends author with the session identity (`SendMessageApi` is now a dumb echo). **D3/US2** — Settings loads the session label and a validated rename persists via `updateLabel` (survives restart). **R4/US3** — `TabBarShell` subscribes to `watchLabel` so the desktop rail account avatar updates live on a rename, no restart. Removed the hardcoded `me`/`You` placeholders. Adversarial multi-agent code-review closed 6 findings (seed-defer on a failed session read; 3 test-strength/coverage; 2 spec-naming). Post-merge gate green (609 tests + 144 goldens).
- **F1+E3+R5 (feature 017) — 2026-07-25 — MERGED into `develop`** (branch `017-file-attachments`, `--no-ff`, merge `1b1cbfd`). Full Spec Kit flow (specify→clarify→plan→tasks→analyze→implement). **F1/US1** — реальный кроссплатформенный пикер за доменным сеймом `FilePickerService` (impl на `file_selector` — `file_picker` конфликтует win32 с `package_info_plus`; metadata-only, `openFile()`+`XFile.length()`, байты не читаются). `ChatThreadBloc._onAttachmentPicked` async→`pickFile()`; реальные name/size/`FileType.fromExtension(ext)` наполняют драфт (заменил хардкод `photo.jpg`); перечитывает `state` после `await`; отмена/сбой→`null`→композер не тронут (никогда не бросает, FR-009). macOS entitlement `files.user-selected.read-only`. **E3/US2** — 5.4 shared-files деривируется из персистентных вложений `MessageDao` (`MessageRepository.chatFiles(chatId)`, newest-first) вместо фабрикованного списка; **016-сейм `ChatFilesRemoteDataSource`/`GetChatFilesApi`/моки/тест — ретайрены** (файлы = локальная деривация, не сетевой ресурс; `ChatRepository.getChatFiles` делегирует). Реальный picker снял риск демо-регресса, из-за которого E3 ранее откладывался (см. supersede ниже). **R5/US3** — вью живой: `ChatCardBloc` watch-ит `watchMessages().skip(1).debounceTime(100ms)` → **invisible** передерив (новый `FilesRefreshed`-event, `copyWith(files:)` — сохраняет List/Grid-выбор и НЕ мигает загрузкой). 5.4-golden перегенерён на bespoke bounded-pump-харнесс (реактивная страница) над non-empty `chat_0`. Мультиагентное adversarial-ревью: 1 подтверждённый MEDIUM (full re-init на live-передериве сбрасывал Grid→List + спиннер-флэш) — исправлен targeted-рефрешем + регресс-тест; 2 LOW (getChatFiles-passthrough / no-op tearDown) отклонены верификацией как осознанные smells. macOS-сборка зелёная (entitlement + плагин линкуются); iOS/Android/Windows/Linux — plugin-standard config, флаг на CI. Пост-мёрж гейт зелёный (629 тестов + 152 голдена).
  - _Supersede E3-отложки:_ запись «E3 — ОТЛОЖЕНО (регрессирует демо 8→1)» ниже закрыта — F1 дал разнообразные реальные вложения, и корректность (files = реально отправленные) теперь ценнее showcase-фабрикации.
- **S4 (feature 018) — 2026-07-26 — MERGED into `develop`** (branch `018-wire-dto-envelope`, `--no-ff`, merge `073a2b5`). Full Spec Kit (specify→clarify→plan→tasks→analyze→implement). Chat-list и message-list на сетевой границе теперь идут через референсный конверт `ResponseEntity<ChatsWireEntity>` / `ResponseEntity<MessagesWireEntity>` (единообразно с Item); генераторы `GetChatsApi`/`GetMessagesApi` оставляют детерминированный model-seed, мапят model→wire (`ChatWireMapper`/`MessageWireMapper`, `lib/data/entity/chat/wire/`) и возвращают конверт; 016-data-source интерфейсы несут конверт; репо разворачивают wire→model в `_seedIfEmpty`/`_seedChatIfEmpty` (`data==null`→throw→`execute()`→`RepositoryResult.error`, как `ItemRepositoryImpl`). Пагинация `page*pageSize<total` == старый `hasMore` для ОБЕИХ схем (ascending chat + descending message — проверено арифметикой). `EntityConverter`-реестр **наполнен** (Item + chat + message wire-сущности резолвятся `fromJson`/`toJson`, неизвестный тип бросает). Own-identity реконсиляция не тронута (идёт post-unwrap над model). **Поведение-нейтрально:** вся consumer-suite без правок, 0 изменений UI, 0 новых голденов (653 теста + 152 голдена). Вне S4: `sendMessage` (одиночный POST-эхо) не завёрнут (отложено). Мультиагентное adversarial-ревью: 0 подтверждённых (3 LOW отклонены верификацией — throw-vs-return идиома / intentional sendMessage-scope / test-helper-формула). Wire-форма — example/TBD до выбора бэкенда. Drift-fix: §5.2 + блюпринт 04.
- **S5 (feature 019) — 2026-07-26 — MERGED into `develop`** (branch `019-auth-apiurl-seam`, `--no-ff`, merge `ee43e6d`). Full Spec Kit (specify→clarify→plan→tasks→analyze→implement). Auth/transport seam: `AppConfig.apiUrl` (nullable TBD → без реального `apiUrl` реальных запросов нет), `AppConfigRepository.getUserAuthIdToken()` (читает `auth_id_token` из secure storage, trim → `null` при пустом/whitespace; писателя пока нет — TBD) + `isTestEnvironment` (env-keyed `@Named`-bool: `@test`→true, `@dev @prod`→false). `AuthInterceptor` (Dio): `onRequest` вешает `Authorization: Bearer <token>` при непустом токене; `onError` на **401** → `authRepository.logout(forced:true)` с **ленивым** разрешением `AuthRepository` (через alias — DI-cycle-safe), всегда пробрасывает. `ApiClient.initBase()`: baseUrl из apiUrl + idempotent-установка interceptor. **Инертно** без apiUrl; `ApiClient` пока не инъектится в data-source. Закрыт док-коммент `AuthRepository` «401 trigger deferred» (401 переиспользует существующий forced-logout-путь → `sessionExpired` → Login; новой навигации нет). Мультиагентное adversarial-ревью: 0 подтверждённых (2 отклонённых как недостижимые в mock-фазе — **оба применены** как дешёвое упрочнение: trim-токена + покрытие `initBase`). Формы apiUrl/токена/заголовка — example/TBD до выбора бэкенда. Пост-мёрж гейт зелёный (666 тестов + 152 голдена). Drift-fix: §5.2.
