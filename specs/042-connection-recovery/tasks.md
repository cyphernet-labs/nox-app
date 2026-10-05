---

description: "Задачи фичи 042 — связь восстанавливается без перезапуска приложения"
---

# Tasks: Связь восстанавливается без перезапуска приложения

**Input**: `specs/042-connection-recovery/` — spec.md, plan.md, research.md, data-model.md, contracts/no-connection-strip.md, quickstart.md

**Prerequisites**: plan.md, spec.md (US1–US3), research.md, data-model.md, contracts/

**Tests**: обязательны (правила проекта): unit/bloc/widget, голдены трёх категорий на обеих ширинах. Каждая задача с кодом проверяется тестом, который падает без неё.

**Organization**: по историям; порядок — слой данных (перезапуск канала, предел выбора пути) → интерфейс (действие на плашке) → голдены → документация.

## Format: `[ID] [P?] [Story] Description`

- **[P]** — можно делать параллельно (разные файлы, нет зависимостей)
- **[Story]** — история из spec.md (US1…US3)

---

## Phase 1: Setup

Нет задач: провод, сервер и хранилище не меняются (plan.md, Constitution Check VII).

---

## Phase 2: Foundational

Нет задач: истории опираются на уже существующие события `retryConnection` трёх блоков, `SessionPhaseService.reconnect()` и `LiveSessionStarter.restart()` (research, п. 1).

---

## Phase 3: User Story 1 — Вернуть связь одним нажатием (Priority: P1) 🎯 MVP

**Goal**: `Try again` на плашке `No connection` в списке чатов, ленте и карточке чата (обе ширины) перезапускает канал с нуля; поднимающийся Tor не теряет прогресс; у неподдерживаемого сервера действия нет.

**Independent Test**: остановить сервер до плашки, запустить его, нажать `Try again` — связь возвращается без перезапуска приложения (quickstart, сценарии 1–2).

### Tests for User Story 1

- [ ] T001 [P] [US1] Тесты в `test/data/sync/connection/connection_path_selector_test.dart`: `end(keepTor: true)` сохраняет Tor-клиент, который готов, спит или поднимается меньше бюджета готовности с момента запуска селектором; останавливает упавший клиент и клиент, который поднимается дольше бюджета (бюджет — параметр `forTest`); `end(keepTor: false)` останавливает всегда, как раньше
- [ ] T002 [P] [US1] Тест там же: после `end(keepTor: true)` и нового `begin(...)` выбор активен со снятым флагом неудачного круга (`roundFailed == false`), а часы отказов ключа забыты — следующий отказ onion-сервиса начинает новый отсчёт; когда новый круг снова не удался, флаг поднимается снова (плашка возвращается, FR-006)
- [ ] T003 [P] [US1] Тесты в `test/data/sync/live_session_starter_test.dart`: `restart()`, вызванный во время уже идущего перезапуска, присоединяется к нему — одна остановка и один запуск канала; `restart()` после завершения предыдущего — новый перезапуск; после `restart()` сокет просит путь сразу, без паузы лестницы, даже если до этого лестница дошла до 30 с (SC-002)
- [ ] T004 [P] [US1] Тесты блоков `test/presentation/pages/chats_list_page/bloc/chats_list_bloc_test.dart`, `test/presentation/pages/chat_card_page/bloc/chat_card_bloc_test.dart`, `test/presentation/pages/chat_thread_page/bloc/chat_thread_bloc_test.dart`: статус `offline` даёт `isOffline == true` и `isUnsupported == false`; статус `unsupported` — `isOffline == true` и `isUnsupported == true`; событие `retryConnection` вызывает `SessionPhaseService.reconnect()` ровно один раз
- [ ] T005 [P] [US1] Виджет-тесты: плашка `No connection` с действием `Try again` при `offline` и без действия при `unsupported`; при `connecting` ни плашки, ни действия (FR-006a); нажатие отправляет `retryConnection` — `test/presentation/pages/chats_list_page/chats_list_page_test.dart` (обе ширины, на широкой — в обеих панелях: списке и ленте без выбранного чата), `test/presentation/widgets/chat/app_thread_view_widget_test.dart`, `test/presentation/pages/chat_card_page/chat_card_page_test.dart`; действие доступно диктору как кнопка с текстом, область нажатия не меньше 48×48

### Implementation for User Story 1

- [ ] T006 [US1] `lib/data/sync/connection/connection_path_selector.dart`: часы подъёма Tor — заводятся, когда селектор запускает остановленный или упавший клиент, снимаются на готовности и остановке; `end(keepTor: true)` оставляет клиент, только если он готов, спит или поднимается меньше `_torReadyBudget`, иначе останавливает (research, п. 2)
- [ ] T007 [US1] `lib/data/sync/live_session_starter.dart`: `restart()` во время идущего перезапуска возвращает тот же `Future` (research, п. 3)
- [ ] T008 [US1] Поле `@Default(false) bool isUnsupported` в `lib/presentation/pages/chats_list_page/bloc/chats_list_state.dart`, `lib/presentation/pages/chat_card_page/bloc/chat_card_state.dart`, `lib/presentation/pages/chat_thread_page/bloc/chat_thread_state.dart`; блоки (`chats_list_bloc.dart`, `chat_card_bloc.dart`, `chat_thread_bloc.dart`) выставляют его вместе с `isOffline` из `ConnectionStatus.state == LinkState.unsupported`
- [ ] T009 [US1] Действие на плашке: `actionLabel: context.l10n.actionTryAgain` и `onAction` с событием `retryConnection`, когда `!isUnsupported`, в `lib/presentation/pages/chats_list_page/chats_list_page.dart`, `lib/presentation/widgets/chat/app_thread_view_widget.dart`, `lib/presentation/pages/chat_card_page/chat_card_page.dart` (по contracts/no-connection-strip.md)

**Checkpoint**: US1 работает и проверяется сама по себе.

---

## Phase 4: User Story 2 — Попытки не останавливаются сами (Priority: P1)

**Goal**: зависший выбор пути бросается не позже 120 с, и следующая попытка начинается сама.

**Independent Test**: поставщик пути, который никогда не отвечает, — попытка брошена по пределу, следующая началась (quickstart, сценарий 4).

### Tests for User Story 2

- [ ] T010 [P] [US2] Тесты в `test/data/remote/socket/nox_socket_client_test.dart`: поставщик пути, чей первый `nextTarget()` не завершается, — по истечении предела выбора (короткий предел, параметр конструктора) попытка брошена, после паузы лестницы приходит второй `nextTarget()`, и соединение по его адресу приветствуется; поздний ответ первого вызова отброшен; остановка и новый запуск сокета во время зависшего `nextTarget()` (так перезапускается канал) сразу просят путь заново, не дожидаясь предела (US1, сценарий 6)
- [ ] T011 [P] [US2] Тест там же: лестница не останавливается — при череде неудач паузы растут до 30 с и не больше, попытки продолжаются; окончательные состояния (`serverMismatch`, `unsupported`) лестницу останавливают, как раньше (добавить, чего ещё нет)

### Implementation for User Story 2

- [ ] T012 [US2] `lib/data/remote/socket/nox_socket_client.dart`: `pathChoiceBudget` (120 с по умолчанию, задаётся в конструкторе для тестов); `targets.nextTarget()` ждётся не дольше него; по пределу — попытка считается «нет пути» (обычная пауза и следующая попытка), номер попытки отбрасывает поздний ответ (research, п. 4)

**Checkpoint**: US1 и US2 работают вместе.

---

## Phase 5: User Story 3 — Вернулся в приложение или сменилась сеть — пробуем сразу (Priority: P2)

**Goal**: закрепить тестами поведение фазы 040: пауза не досиживается; идущая попытка на переднем плане не перезапускается.

**Independent Test**: при плашке `No connection` вернуть приложение на передний план или сменить сеть — попытка началась сразу (quickstart, сценарий 3).

### Tests for User Story 3

- [ ] T013 [P] [US3] Тесты в `test/data/sync/connection/connection_path_selector_test.dart` (добавить недостающие): возврат на передний план, пока сокет ждёт паузу, сразу вызывает `reconnect()`; возврат во время идущей попытки — не вызывает; смена сети без связи сразу вызывает `reconnect()`; при живом соединении возврат на передний план соединение не рвёт

### Implementation for User Story 3

- [ ] T014 [US3] Если какой-то тест T013 падает — исправить в `lib/data/sync/connection/connection_path_selector.dart`; иначе задача закрывается без изменений кода

**Checkpoint**: все истории работают.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T015 [P] Голдены (SC-005): обновить шесть снимков «нет связи» — `test/presentation/pages/chats_list_page/goldens/chats_list_page_offline_{light,dark}.png`, `test/presentation/pages/chat_thread_page/goldens/chat_thread_page_offline{,_desktop}_{light,dark}.png`, `test/presentation/pages/chat_card_page/goldens/chat_card_page_offline{,_desktop}_{light,dark}.png`; добавить десктопный снимок списка без связи `goldenTestDesktop('chats_list_page_offline', …)` в `test/presentation/pages/chats_list_page/chats_list_page_golden_test.dart`
- [ ] T016 [P] Документация: `docs/design/spec/screens/{chats-list,chat,chat-card}.md` (плашка с действием, исключение для неподдерживаемого сервера); `docs/design/system/nox-mobile-screens/screens/{5-1-chats,5-2-thread,5-4-card}.md` и `specs.js`; `docs/design/system/nox-desktop-screens/screens/{01-chats,09-drawer}.md` и `specs.js`; `docs/blueprints/mobile/14-networking-and-auth.md` (`Try again` = перезапуск канала, перезапуск сохраняет только здоровый Tor, предел выбора пути 120 с); `CLAUDE.md`
- [ ] T017 Гейты: `make gate`, `make golden-verify`; счётчики в `CLAUDE.md`
- [ ] T018 Проверка на стенде по `quickstart.md` (сценарии 1–3) — владелец

---

## Dependencies & Execution Order

- Phase 1–2 — пусто.
- **US1** (Phase 3) и **US2** (Phase 4) независимы: разные файлы (селектор/стартер/UI против сокета).
- **US3** (Phase 5) — только тесты селектора; может идти параллельно с US1, но T013 и T001/T002 — один файл, писать по очереди.
- **Polish**: T015 — после T009; T016 — после всех историй; T017 — последним из кода.

### Within each story

Тесты пишутся первыми и падают без реализации; затем реализация.

## Parallel Example: User Story 1

```text
T001, T002 (селектор) — один файл, подряд
T003 (стартер), T004 (блоки), T005 (виджеты) — параллельно с ними
```

## Implementation Strategy

### MVP First (User Story 1)

US1 одна закрывает замечание владельца: появляется действие вместо перезапуска. US2 убирает причину, по которой без действия связь не возвращалась сама. US3 — закрепление уже существующего поведения.

### Incremental Delivery

1. US1 → проверка сценариев 1–2 quickstart.
2. US2 → тест зависшего выбора пути.
3. US3 → тесты переднего плана и смены сети.
4. Голдены, документация, гейты.
