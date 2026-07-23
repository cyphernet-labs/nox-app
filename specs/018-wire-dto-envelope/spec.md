# Feature Specification: Uniform wire-DTO envelope for chat & message (S4)

**Feature Branch**: `018-wire-dto-envelope`

**Created**: 2026-07-25

**Status**: Draft

**Input**: User description: S4 — провести chat/message через `ResponseEntity` + `EntityConverter` (wire-DTO), как Item-harness; наполнить пустой `EntityConverter`. Mock/TBD-плейсхолдер, реальный бэкенд-контракт не изобретаем.

## Контекст и цель

NOX сознательно **не выбрал** транспорт/протокол/сервер. Data-слой уже имеет **референсный конверт** для будущей интеграции: `ResponseEntity<T>` (унифицированный envelope) + `EntityConverter` (реестр, резолвящий `T` в конкретную entity). Сегодня через этот конверт идёт **только Item** (`ResponseEntity<ItemsEntity>`, `ItemEntity`/`ItemsEntity` + `ItemMapper`); генераторы chat/message (`GetChatsApi`/`GetMessagesApi`) возвращают **доменные модели напрямую** — это единственная неохваченная сетевая граница. Реестр `EntityConverter` **пуст** и бросает для любого типа.

Задача — привести chat-list и message-list к тому же референсному конверту (без изменения того, что видит UI), и наполнить реестр `EntityConverter`. Это **подготовка seam'а**: когда бэкенд выберут, интеграция станет локализованной заменой байндинга data-source, а репозитории/DAO/мапперы/`RepositoryResult`/`PageMetadata`/UI останутся нетронутыми. Конверт остаётся **example/TBD** — реальная wire-форма заменит его при выборе бэкенда.

**«Пользователь» этой фичи — разработчик/будущая интеграция бэкенда**, а не конечный пользователь: у фичи нет user-facing поведения (0 изменений UI).

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

- **SC-001**: 100% существующих chat/message репо/BLoC/страничных тестов проходят **без правок** (доказательство неизменного поведения, FR-006).
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
- Изменение доменных моделей, локальных Sembast-сущностей, DAO, cache-first-семантики, seed-данных, UI/BLoC.
- Новые голдены; изменение пользовательского поведения любого рода.
