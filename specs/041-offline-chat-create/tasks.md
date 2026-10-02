---

description: "Задачи фичи 041 — чат без связи"
---

# Tasks: Чат без связи — появляется сразу, на сервере — когда будет связь

**Input**: `specs/041-offline-chat-create/` — spec.md, plan.md, research.md, data-model.md, contracts/chat-create.md, quickstart.md

**Prerequisites**: plan.md, spec.md (US1–US5), research.md, data-model.md, contracts/

**Tests**: обязательны (решение владельца и правила проекта): unit/bloc/widget, голдены трёх категорий на обеих ширинах, `go test -race`. Каждая задача с кодом проверяется тестом, который падает без неё.

**Organization**: по историям; порядок — контракт → сервер → data-слой и очередь клиента → UI → документация.

## Format: `[ID] [P?] [Story] Description`

- **[P]** — можно делать параллельно (разные файлы, нет зависимостей)
- **[Story]** — история из spec.md (US1…US5)

---

## Phase 1: Setup (контракт — сначала)

**Purpose**: Принцип VII — изменение провода сначала вносится в контракт.

- [ ] T001 Внести в `docs/client-backend/protocol/contract-draft.md` §4: `chat.create {name, chat_id?}`, вид `^c_[0-9a-f]{32}$`, порядок проверок (вид → существующий id → имя → вставка), повтор существующего id без записи и без события, `invalid_request` на неверный вид, совместимость по правилу §2.1 (сервер без поддержки пропускает поле; клиент сверяет id в ответе) — по `specs/041-offline-chat-create/contracts/chat-create.md`

---

## Phase 2: Foundational (сервер и общая основа клиента)

**Purpose**: то, на чём стоят все истории: сервер принимает `chat_id`, у чата появляется состояние создания, у очереди — перенос записей.

**⚠️ CRITICAL**: истории начинаются после этой фазы.

### Сервер

- [ ] T002 [P] Тесты хранилища в `client_backend/internal/store/store_test.go`: `CreateChat` с id устройства создаёт чат под ним и одно событие `chat.created` с этим id; повтор с тем же id возвращает существующий чат, второй строки и второго события нет; повтор после переименования возвращает нынешнее имя; повтор существующего id никогда не даёт `ErrNameTaken`, даже при совпавшем имени; новый id с занятым именем — `ErrNameTaken`; без id — серверный `c_` + 16 hex
- [ ] T003 `Store.CreateChat` в `client_backend/internal/store/store.go`: параметр `chatID`; в одной пишущей транзакции сначала поиск по id (найден — возврат без записи и с признаком «не создавался»), затем проверка имени, затем вставка с данным или серверным id и событием
- [ ] T004 [P] Тесты провода в `client_backend/internal/server/chats_test.go`: `chat.create` с `chat_id` — ответ и событие несут его; повтор — тот же чат и ни одного нового события у подписчиков; неверный вид — `invalid_request`; без `chat_id` — как раньше
- [ ] T005 Обработчик `chat.create` в `client_backend/internal/server/handlers.go`: поле `chat_id` в `chatCreateRequest`, проверка вида `^c_[0-9a-f]{32}$`, вызов `CreateChat`, `kickDispatcher` только когда чат создан; в строках лога — только id и коды, имя чата не попадает никогда (FR-022, проверяется ревью диффа)

### Клиент: модель и хранение

- [ ] T006 [P] `mintChatId()` в `lib/general/id/chat_id.dart` (`c_` + 32 hex из `Random.secure()`) и тест вида и неповторяемости в `test/general/id/chat_id_test.dart`
- [ ] T007 [P] Доменное перечисление `ChatCreation { pending, nameTaken, failed }` в `lib/domain/model/chat/chat_creation.dart` и поле `ChatCreation? creation` в `lib/domain/model/chat/chat_model.dart`
- [ ] T008 Поля `String? creation` и `int? creationAttempts` в `lib/data/entity/chat/chat_entity.dart`; перевод в обе стороны в `lib/data/mapper/chat/chat_mapper.dart`; тест (старая запись без полей читается как созданный чат) в `test/data/mapper/chat/chat_mapper_test.dart`
- [ ] T009 `ChatDao.pendingCreations()` (фильтр в Dart, старые первыми) и `ChatDao.delete(id)` в `lib/data/local/chat/chat_dao.dart`; тесты в `test/data/local/chat/chat_dao_test.dart`
- [ ] T010 [P] `createChat({required String name, String? chatId})` в `lib/data/remote/datasource/chat_remote_data_source.dart`, `real/real_chat_remote_data_source.dart` (шлёт `chat_id`) и `mock/mock_chat_remote_data_source.dart` (берёт присланный id)
- [ ] T011 [P] `OutboxRepository.moveChat({required String from, required String to})` в `lib/domain/repository/chat/outbox_repository.dart`, `lib/data/repository/chat/outbox_repository_impl.dart`, `lib/data/local/chat/outbox_dao.dart`; тест в `test/data/repository/chat/outbox_repository_impl_test.dart`

**Checkpoint**: сервер принимает `chat_id` идемпотентно; у чата на устройстве есть состояние создания.

---

## Phase 3: User Story 1 — Завести чат без связи и сразу писать в него (Priority: P1) 🎯 MVP

**Goal**: чат создаётся на устройстве сразу, сообщения в него ждут, при связи чат и сообщения уходят по порядку.

**Independent Test**: без связи создать чат, написать три сообщения, вернуть связь — чат на сервере, сообщения по порядку, отметки ушли (quickstart, сценарий 1).

### Tests for User Story 1

- [ ] T012 [P] [US1] Тесты репозитория в `test/data/repository/chat/chat_repository_impl_test.dart`: `createChat` не обращается к серверу, пишет строку с `pending`, id вида `c_` + 32 hex и строку «Chat created by …»; `pendingCreations` отдаёт её; `createOnServer` с тем же id снимает состояние
- [ ] T013 [P] [US1] Тесты очереди в `test/data/sync/outbox_service_test.dart`: создание раньше сообщений; сообщения ждущего чата не отправляются и не тратят попыток; сообщения других чатов идут; после создания в том же проходе сообщения чата уходят по порядку; повторяемый отказ оставляет `pending`, считает попытку и ставит паузу; после «перезапуска» (новый сервис) создание подхватывается
- [ ] T014 [P] [US1] Тест синхронизации в `test/data/sync/sync_service_test.dart`: `chat.created` для ждущего чата снимает состояние и сохраняет метку прочтения
- [ ] T015 [P] [US1] Тесты `test/presentation/pages/create_chat_page/bloc/create_chat_bloc_test.dart`: `Create` ведёт в чат с id устройства без ответа сервера и просит очередь пройти

### Implementation for User Story 1

- [ ] T016 [US1] В `lib/domain/repository/chat/chat_repository.dart` и `lib/data/repository/chat/chat_repository_impl.dart`: `createChat` на устройстве (`mintChatId`, строка с `pending`, `seedCreatedChat`); `pendingCreations()`; `createOnServer({required ChatModel chat})` — `chat.create` с `chat_id`, запись ответа сервера без состояния; `markCreation({chatId, creation, attempts})`; исправить устаревший докстринг о network-only
- [ ] T017 [US1] `lib/data/sync/outbox_service.dart`: проход создаёт ждущие чаты раньше сообщений; сообщения чатов с `creation != null` пропускаются без попытки; повторяемые отказы — пауза по лестнице очереди с ключом `create:<chat_id>` и попытками из строки чата; в строках лога — только id и коды, имя чата не попадает никогда (FR-022, проверяется ревью диффа)
- [ ] T017a [US1] `lib/data/repository/chat/message_repository_impl.dart`: окно сообщений (`getMessages` без `cachedOnly`) и `chatFiles(refresh: true)` не ходят на сервер, пока у чата есть состояние создания (FR-007a); тест в `test/data/repository/chat/message_repository_impl_test.dart` — фейковый источник не вызывается, кэш отдаётся
- [ ] T018 [US1] `lib/data/sync/sync_service.dart` `_applyChat`: строка из провода снимает состояние создания
- [ ] T019 [US1] `lib/presentation/pages/create_chat_page/bloc/create_chat_bloc.dart`: создание без ожидания сервера и `OutboxService.flush()` после него; ошибки сети в реальном потоке больше нет (отказ возможен только при сбое локальной записи — `networkError` не показывается за сеть), демонстрационные исходы для голденов остаются
- [ ] T020 [P] [US1] Строки EN + UK в `lib/l10n/app_en.arb` и `lib/l10n/app_uk.arb`: имя для диктора «ждёт создания», `Name already taken`, `Couldn't create`, плашки ленты для трёх состояний, действие `Rename`
- [ ] T021 [US1] `lib/presentation/widgets/chat/app_chat_item_widget.dart`: параметр состояния создания — часики вместо времени для `pending` с текстовым именем; тест в `test/presentation/widgets/chat/app_chat_item_widget_test.dart`
- [ ] T022 [US1] `lib/presentation/pages/chats_list_page/chats_list_page.dart`: передать `chat.creation` в строку на обеих ширинах
- [ ] T023 [US1] Плашка «ждёт создания» в `lib/presentation/widgets/chat/app_thread_view_widget.dart` — только пока канал не текущий; состояние читается через `WatchChat`; тест в `test/presentation/widgets/chat/app_thread_view_widget_test.dart`

**Checkpoint**: US1 работает и проверяется сама по себе.

---

## Phase 4: User Story 2 — Создание никогда не ждёт сервер (Priority: P1)

**Goal**: при связи создание тоже не ждёт ответа; проверка имени не держит `Create`.

**Independent Test**: создать чат через медленный путь — чат открыт до ответа сервера (quickstart, сценарий 2).

- [ ] T024 [P] [US2] Тест в `test/presentation/pages/create_chat_page/bloc/create_chat_bloc_test.dart`: при сервере, который не отвечает, `Create` ведёт в чат сразу
- [ ] T025 [P] [US2] Тест там же: проверка имени при отказе сервера `connection` даёт `valid` и не держит `Create`

---

## Phase 5: User Story 3 — Имя занято: переименовать, и чат создастся сам (Priority: P2)

**Goal**: `name_taken` помечает чат; переименование на устройстве возвращает создание в ход.

**Independent Test**: quickstart, сценарий 3.

### Tests for User Story 3

- [ ] T026 [P] [US3] Тесты очереди в `test/data/sync/outbox_service_test.dart`: `name_taken` даёт `nameTaken`, сообщения ждут, новых попыток нет; прочий окончательный отказ даёт `failed`; после `renameLocally` / `retryCreation` чат создаётся и сообщения уходят
- [ ] T027 [P] [US3] Тесты в `test/presentation/widgets/chat/rename_chat_dialog/rename_chat_bloc_test.dart`: чат, которого нет на сервере, переименовывается на устройстве без обращения к серверу и возвращается в `pending`; созданный — как раньше

### Implementation for User Story 3

- [ ] T028 [US3] `ChatRepository.renameLocally({chatId, name})` и `retryCreation({chatId})` в `lib/domain/repository/chat/chat_repository.dart` и `lib/data/repository/chat/chat_repository_impl.dart`; тесты в `test/data/repository/chat/chat_repository_impl_test.dart`
- [ ] T029 [US3] Исходы `name_taken` и прочих окончательных отказов в `lib/data/sync/outbox_service.dart`
- [ ] T030 [US3] `lib/presentation/widgets/chat/rename_chat_dialog/rename_chat_bloc.dart`: ветка для чата, которого нет на сервере, и `OutboxService.flush()` после неё
- [ ] T031 [US3] Строка списка для `nameTaken`/`failed` (знак ошибки вместо времени, строка состояния вместо превью) в `lib/presentation/widgets/chat/app_chat_item_widget.dart`; тест
- [ ] T032 [US3] Плашки ленты: «имя занято» с `Rename` (открывает `AppRenameChatDialogWidget.show`) и «не создан» с `Try again` (`retryCreation` + `flush`) в `lib/presentation/widgets/chat/app_thread_view_widget.dart`; тесты

**Checkpoint**: US3 работает и проверяется сама по себе.

---

## Phase 6: User Story 4 — Повторы не создают второй чат (Priority: P2)

**Goal**: обрыв посреди создания не плодит дублей.

**Independent Test**: тесты сервера (T002, T004) и клиента ниже.

- [ ] T033 [P] [US4] Тест очереди в `test/data/sync/outbox_service_test.dart`: ответ на создание потерян (`connection` после записи на сервере) — повтор с тем же id возвращает тот же чат, на устройстве один чат; если событие `chat.created` пришло раньше повтора, создание больше не отправляется

---

## Phase 7: User Story 5 — Сервер старее этой фичи (Priority: P3)

**Goal**: ответ с другим id принимается без потерь.

**Independent Test**: тест очереди с фейковым источником, отвечающим своим id.

- [ ] T034 [P] [US5] Тест в `test/data/sync/outbox_service_test.dart`: ответ с другим id — в списке один чат под id сервера, ждавшие сообщения перенесены и уходят в него, локальная строка и её «Chat created by …» удалены
- [ ] T035 [US5] `ChatRepository.adoptServerChat({localId, serverChat})` в `lib/data/repository/chat/chat_repository_impl.dart` и перенос в `lib/data/sync/outbox_service.dart` (сначала `moveChat`, потом удаление локальной строки)

---

## Phase 8: Polish & Cross-Cutting Concerns

- [ ] T036 [P] Голдены (SC-005): все три состояния строки в `test/presentation/widgets/chat/app_chat_item_widget_golden_test.dart`; список с чатами во всех трёх состояниях на обеих ширинах в `test/presentation/pages/chats_list_page/chats_list_page_golden_test.dart`; лента с плашками «ждёт создания» (без канала) и «имя занято» на обеих ширинах в `test/presentation/pages/chat_thread_page/chat_thread_page_golden_test.dart`
- [ ] T037 [P] Тесты FR-021: после выхода из аккаунта ждущие чаты стёрты и создание не уходит — `test/data/repository/app/auth_repository_impl_test.dart`; после смены мира (другой журнал сервера) — так же — `test/data/sync/live_session_starter_test.dart`
- [ ] T038 [P] Документация: `docs/design/spec/screens/{chats-list,chat,create-chat,chat-card}.md`; `docs/design/system/nox-mobile-screens/screens/{5-1-chats,5-2-thread,6-1-create}.md` и `specs.js`; `docs/design/system/nox-desktop-screens/screens/{01-chats,07-create}.md` и `specs.js`; `docs/blueprints/mobile/04-data-layer.md` и `14-networking-and-auth.md`; `CLAUDE.md`
- [ ] T039 Гейты: `make gate`, `make golden-verify`, `(cd client_backend && go test -race ./...)`; счётчики в `CLAUDE.md`
- [ ] T040 Проверка на стенде по `quickstart.md` (сценарии 1–3) — владелец

---

## Dependencies & Execution Order

- **Phase 1 → Phase 2 → истории.** Контракт до кода; сервер (T002–T005) и клиентская основа (T006–T011) — до историй.
- **US1 (P1)** — основа всех остальных историй (очередь создаёт, строка и плашка показывают).
- **US2** — проверки поверх US1.
- **US3** — после US1 (те же очередь и строка).
- **US4** — после US1; серверная часть уже в Phase 2.
- **US5** — после US1 и T011.
- **Polish** — после всех историй.

### Parallel Opportunities

- T002 и T004 (тесты сервера) — параллельно с T006, T007, T010, T011 (клиент).
- Внутри US1: тесты T012–T015 параллельно; T020 (строки) параллельно с кодом.
- US4 (T033) и US5 (T034) — параллельно после US1.

## Implementation Strategy

1. Контракт (T001), затем сервер (T002–T005) — `go test -race` зелёный.
2. Клиентская основа (T006–T011).
3. **MVP — US1**: чат создаётся без связи и доходит до сервера с сообщениями.
4. US2–US5 — дополнения поверх.
5. Документация, голдены, гейты; стенд — владелец.
