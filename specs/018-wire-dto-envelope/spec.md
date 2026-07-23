# Feature Specification: Uniform wire-DTO envelope for chat & message (S4)

**Feature Branch**: `018-wire-dto-envelope`

**Created**: 2026-07-25

**Status**: Draft

**Input**: User description: S4 — провести chat/message через `ResponseEntity` + `EntityConverter` (wire-DTO), как Item-harness; наполнить пустой `EntityConverter`. Mock/TBD-плейсхолдер, реальный бэкенд-контракт не изобретаем.

## Контекст и цель

NOX сознательно **не выбрал** транспорт/протокол/сервер. Data-слой уже имеет **референсный конверт** для будущей интеграции: `ResponseEntity<T>` (унифицированный envelope) + `EntityConverter` (реестр, резолвящий `T` в конкретную entity). Сегодня через этот конверт идёт **только Item** (`ResponseEntity<ItemsEntity>`, `ItemEntity`/`ItemsEntity` + `ItemMapper`); генераторы chat/message (`GetChatsApi`/`GetMessagesApi`) возвращают **доменные модели напрямую** — это единственная неохваченная сетевая граница. Реестр `EntityConverter` **пуст** и бросает для любого типа.

Задача — привести chat-list и message-list к тому же референсному конверту (без изменения того, что видит UI), и наполнить реестр `EntityConverter`. Это **подготовка seam'а**: когда бэкенд выберут, интеграция станет локализованной заменой байндинга data-source, а репозитории/DAO/мапперы/`RepositoryResult`/`PageMetadata`/UI останутся нетронутыми. Конверт остаётся **example/TBD** — реальная wire-форма заменит его при выборе бэкенда.

**«Пользователь» этой фичи — разработчик/будущая интеграция бэкенда**, а не конечный пользователь: у фичи нет user-facing поведения (0 изменений UI).

## Clarifications

### Session 2026-07-25

- Q: Несёт ли сетевая граница конверт — меняется ли сигнатура 016-интерфейсов `ChatRemoteDataSource`/`MessageRemoteDataSource` на возврат `ResponseEntity<wire>` (как `ItemRemoteDataSource`), или конверт заворачивается только внутри генератора? → A: **Да, граница несёт конверт.** `ChatRemoteDataSource.getChats` → `Future<ResponseEntity<ChatsWireEntity>>` и `MessageRemoteDataSource.getMessages` → `Future<ResponseEntity<MessagesWireEntity>>` (зеркалит `ItemRemoteDataSource.getItems → Future<ResponseEntity<ItemsEntity>>`); репозиторий разворачивает. Так все четыре data-source единообразны, а флип-на-бэкенд — истинная замена байндинга. `sendMessage` (одиночный POST-эхо) остаётся вне конверта в этой фиче — см. ниже.
- Q: `sendMessage` (одиночная отправка, `MessageRemoteDataSource.sendMessage`) — тоже заворачивать в `ResponseEntity`? → A: **Нет, вне scope S4.** S4 покрывает пагинируемые LIST-боундери (chat-list, message-list), симметрично Item-harness (тоже list). `sendMessage` — одиночный echo-POST; его конверт-форма (одиночный `ResponseEntity<MessageWireEntity>`) — отдельная, меньшая задача, отложена, чтобы не расширять срез (документируем в Out of Scope).
- Q: Где живут wire-сущности и как переиспользуется существующий seed? → A: **Plan-level:** wire-сущности в `lib/data/entity/chat/wire/` (видимо отдельно от локальных Sembast-сущностей); бидирекциональный `wire↔model`-маппер; генератор оставляет существующий model-shaped seed и мапит `model→wire` (round-trip доказывает маппер в обе стороны), репо разворачивает `wire→model`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Chat-list идёт через референсный конверт (Priority: P1)

Список чатов на сетевой границе оборачивается в `ResponseEntity<ChatsWireEntity>` (как Item в `ResponseEntity<ItemsEntity>`), а репозиторий разворачивает конверт и отдаёт те же доменные `ChatModel`, что и раньше.

**Why this priority**: Первый из двух неохваченных боундери; доказывает, что паттерн Item переносится на реальную (пагинируемую, cache-first) фичу без изменения хранилища и UI.

**Independent Test**: Прогнать существующие chat-репо/BLoC/список-тесты — они проходят без правок (те же `ChatModel`), плюс новый тест: mock-источник отдаёт `ResponseEntity<ChatsWireEntity>` → репо разворачивает в идентичный прежнему список `ChatModel` + `PageMetadata`.

**Acceptance Scenarios**:

1. **Given** засеянный мок-набор чатов, **When** репозиторий запрашивает страницу, **Then** он получает `ResponseEntity<ChatsWireEntity>` и разворачивает её в тот же `(List<ChatModel>, PageMetadata)`, что и до фичи (побайтово то же доменное содержимое: id/name/preview/lastMessageAt/unread, порядок, пагинация).
2. **Given** конверт с `success:false` / пустым `data`, **When** репозиторий его разворачивает, **Then** он возвращает `RepositoryResult.error` (как `ItemRepositoryImpl` для пустого `data`), не роняя приложение.
3. **Given** wire-entity чата, **When** её сериализуют в JSON и обратно, **Then** round-trip восстанавливает те же поля (детеминированно).

---

### User Story 2 — Message-list идёт через референсный конверт (Priority: P1)

История сообщений чата на сетевой границе оборачивается в `ResponseEntity<MessagesWireEntity>`, репозиторий разворачивает её в те же доменные `MessageModel` (включая вложение), что и раньше.

**Why this priority**: Второй неохваченный боундери; сообщения несут вложение (nested wire-shape) — доказывает конверт на более богатой сущности.

**Independent Test**: Существующие message-репо/тред-тесты проходят без правок; новый тест: mock-источник отдаёт `ResponseEntity<MessagesWireEntity>` → репо разворачивает в идентичный прежнему список `MessageModel` (текст/автор/статус/isSystem/вложение) + `PageMetadata`.

**Acceptance Scenarios**:

1. **Given** засеянную историю чата (с одним вложением), **When** репозиторий запрашивает страницу, **Then** он получает `ResponseEntity<MessagesWireEntity>` и разворачивает её в тот же `(List<MessageModel>, PageMetadata)`, включая вложение (id/type/name/sizeBytes) и системную строку.
2. **Given** конверт с `success:false` / пустым `data`, **When** репозиторий его разворачивает, **Then** он возвращает `RepositoryResult.error`.
3. **Given** wire-entity сообщения (с вложением и без), **When** её сериализуют в JSON и обратно, **Then** round-trip восстанавливает те же поля.

---

### User Story 3 — Реестр `EntityConverter` резолвит все wire-сущности (Priority: P2)

Реестр `EntityConverter` наполняется всеми сущностями, достижимыми через `ResponseEntity<T>` (Item + chat + message), так что `ResponseEntity.fromJson`/`toJson` их резолвит (сегодня бросает для любого типа) — референсный harness завершён.

**Why this priority**: Завершает конверт: без наполненного реестра `fromJson` реального ответа бэкенда упадёт. Отдельная стори, т.к. это единая точка (реестр), покрывающая обе фичи.

**Independent Test**: Для каждой зарегистрированной wire-сущности `ResponseEntity<T>.fromJson(<json>)` возвращает типизированную сущность (не бросает), а `toJson` даёт симметричный map; неизвестный тип по-прежнему явно бросает `ArgumentError`.

**Acceptance Scenarios**:

1. **Given** JSON-конверт `{success, data}` для каждой зарегистрированной `T` (Item/Items, ChatWire/ChatsWire, MessageWire/MessagesWire), **When** его парсят через `ResponseEntity<T>.fromJson`, **Then** `data` резолвится в конкретную сущность `T`, а не бросает.
2. **Given** сущность `T`, **When** `ResponseEntity<T>(data: entity).toJson()`, **Then** `data` сериализуется в map (симметрично `fromJson`).
3. **Given** тип, не зарегистрированный в реестре, **When** его резолвят, **Then** реестр бросает `ArgumentError` (явный контракт «нет конвертера»).

---

### Edge Cases

- **Пустая/финальная страница пагинации** — `hasMore` вычисляется из `page*pageSize < total` (как у Item), последняя страница даёт `nextPage: null`.
- **`data == null` при `success:true`** — трактуется как ошибка распаковки → `RepositoryResult.error` (нет данных для маппинга).
- **Вложение отсутствует** — message wire-entity с `attachment == null` разворачивается в `MessageModel` без вложения (nullable сквозь весь путь).
- **Локальная Sembast-сущность vs wire-сущность** — это РАЗНЫЕ формы: wire только на сетевой границе, локальная (`ChatEntity`/`MessageEntity`) остаётся формой хранения; никакой путаницы имён (wire несёт суффикс `Wire`).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Ввести JSON-сериализуемые **wire-сущности** для списка чатов и списка сообщений (элемент + страница-конверт), смоделированные на существующих `ItemEntity`/`ItemsEntity`, включая поля пагинации (`page`/`pageSize`/`total`).
- **FR-002**: Wire-сущности MUST быть **отдельными** от локальных Sembast-сущностей (`ChatEntity`/`MessageEntity`) и нести различимое имя (`*WireEntity`), чтобы форма хранения и форма сети не смешивались.
- **FR-003**: Ввести маппинг **wire-сущность → доменная модель** (по образцу `ItemMapper`), покрывающий все поля, включая coercion (enum/DateTime/nested вложение).
- **FR-004**: Мок-источники chat/message MUST возвращать `ResponseEntity<ChatsWireEntity>` / `ResponseEntity<MessagesWireEntity>` (как `GetItemsApi` — `ResponseEntity<ItemsEntity>`), сохраняя тот же детерминированный seed и ту же пагинацию.
- **FR-005**: Репозитории chat/message MUST разворачивать конверт **тем же способом**, что `ItemRepositoryImpl` (проверка `data == null` → `RepositoryResult.error`, иначе маппинг + `PageMetadata`), и отдавать те же доменные модели, что и до фичи.
- **FR-006**: Поведение, видимое UI/BLoC/потребителям репозитория, MUST остаться **байт-в-байт неизменным** (те же доменные модели, порядок, пагинация, cache-first Sembast-семантика, seed-данные).
- **FR-007**: Реестр `EntityConverter` MUST быть наполнен всеми wire-сущностями, достижимыми через `ResponseEntity<T>` (Item + chat + message), так что `fromJson`/`toJson` их резолвит; неизвестный тип MUST по-прежнему явно бросать.
- **FR-008**: Cache-first Sembast-хранение и локальные сущности/мапперы/DAO MUST остаться нетронутыми (wire-форма — только сетевая граница).
- **FR-009**: Никаких реальных сетевых вызовов, auth, apiUrl, HMAC — это отдельный seam (S5); конверт остаётся example/**TBD**, документирован как заменяемый реальной wire-формой при выборе бэкенда.
- **FR-010**: Флип-на-бэкенд MUST остаться локализованной заменой байндинга data-source (репо/DAO/мапперы/`RepositoryResult`/`PageMetadata`/UI не трогаются) — задокументировать.

### Key Entities *(include if feature involves data)*

- **ChatWireEntity / ChatsWireEntity** — сетевая форма одного чата / страницы чатов (элементы + `page`/`pageSize`/`total`). JSON-сериализуема, достижима через `ResponseEntity`.
- **MessageWireEntity / MessagesWireEntity** — сетевая форма одного сообщения (с опциональным вложением) / страницы сообщений. JSON-сериализуема.
- **ResponseEntity<T>** *(существует)* — унифицированный envelope `{success, error, data}`; `data` резолвится реестром.
- **EntityConverter** *(существует, пуст)* — ручной реестр `T` → fromJson/toJson; наполняется всеми wire-сущностями.
- **ChatModel / MessageModel** *(существуют, не меняются)* — доменные модели, которые репозитории продолжают отдавать без изменений.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% существующих **потребительских** тестов (chat/message репо, `ChatsListBloc`/`ChatThreadBloc`, страничные/golden) проходят **без правок** — доказательство неизменного поведения (FR-006). Исключение (ожидаемое): два **генераторных** теста (`get_chats_api_test`, `get_messages_api_test`) обновляются под новый контракт генератора (его возвращаемый тип поменялся с кортежа на `ResponseEntity<wire>` — это и есть предмет фичи, а не регресс поведения).
- **SC-002**: Каждая зарегистрированная wire-сущность проходит JSON round-trip (`fromJson∘toJson` восстанавливает поля) — 0 непокрытых зарегистрированных типов.
- **SC-003**: Оба репозитория (chat, message) разворачивают `ResponseEntity` в те же доменные модели, что и до фичи; пустой/`success:false` конверт → `RepositoryResult.error` (как Item).
- **SC-004**: Число неохваченных конвертом сетевых боундери падает с 2 (chat, message) до 0 — весь network-boundary идёт через `ResponseEntity` единообразно.
- **SC-005**: 0 изменений UI, 0 новых голденов, `make gate` + `make golden-verify` зелёные.
- **SC-006**: Флип-на-бэкенд остаётся документированной локализованной заменой байндинга (репо/DAO/мапперы/UI не трогаются).

## Assumptions

- Wire-сущности **зеркалят доменные поля** (без потери информации), а не изобретают backend-специфичную форму — конверт остаётся TBD/example и заменится реальной формой при выборе бэкенда.
- Пагинация в wire-list-сущности повторяет `ItemsEntity` (`page`/`pageSize`/`total`), `hasMore` = `page*pageSize < total`.
- Мок-генераторы chat/message продолжают синтезировать тот же детерминированный seed; меняется только внешняя форма (доменная модель → `ResponseEntity<wire>`), внутренний seed — тот же.
- Строки времени/enum в wire несут ту же ISO/`name`-кодировку, что уже используют локальные сущности/Item-референс.

## Out of Scope

- Реальный транспорт, сервер, auth-токен, apiUrl, HMAC/security-заголовки (S5 — отдельная фича).
- `sendMessage` (одиночный echo-POST) через `ResponseEntity<MessageWireEntity>` — отложено (S4 покрывает пагинируемые LIST-боундери симметрично Item; одиночный POST-конверт — отдельная меньшая задача).
- Изменение доменных моделей, локальных Sembast-сущностей, DAO, cache-first-семантики, seed-данных, UI/BLoC.
- Новые голдены; изменение пользовательского поведения любого рода.
