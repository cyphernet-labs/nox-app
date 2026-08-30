# Tasks: client-live-exchange

**Input**: Design documents from `/specs/026-client-live-exchange/` (plan.md, research.md R1–R13, data-model.md, contracts/README.md, quickstart.md)

**Prerequisites**: ветка ответвлена от 025; `make gate` + `make golden-verify` зелёные на старте (эталон заморозки); `noxd` собирается.

**Tests**: тесты включены — фаза меняет data-слой, на котором держится вся продуктовая логика, а живая проверка ручная. Тестовое окружение остаётся на моках (research R13), поэтому весь набор проходит без запущенного сервера.

**Organization**: фундамент — транспорт и фазы сессии (без него ни одна история не двигается), затем истории спеки по приоритету.

## Phase 1: Setup

- [ ] T001 Verify the freeze baseline: run `make gate` and `make golden-verify`, and record the current test count as the number the phase must not reduce
- [ ] T002 Promote `web_socket_channel` to a direct dependency in pubspec.yaml pinned to the already-locked 3.0.3 (research R1), then `make deps` and confirm pubspec.lock shows no other version movement

## Phase 2: Foundational (blocking prerequisites)

**Purpose**: транспорт, фазы сессии и эпоха источника — без них ни одна история не существует.

- [ ] T003 [P] Add the session-phase domain types in lib/domain/model/session/session_phase.dart (enum disconnected/connecting/catchingUp/live) and lib/domain/model/session/server_identity.dart (`{id, label}`), per data-model.md
- [ ] T004 [P] Add `maxLimit = 100` to lib/domain/repository/chat/get_messages_config.dart and clamp it inside the `tail` and `olderThan` factories (research R9, FR-010); update test/domain/repository/chat/get_messages_config_test.dart to assert the clamp
- [ ] T005 Add the frame model and channel seam in lib/data/remote/socket/: server_event.dart (`{seq, event, data}`) and socket_channel_factory.dart (injectable factory so tests supply an in-memory channel instead of a real socket, research R13)
- [ ] T006 Implement lib/data/remote/socket/nox_socket_client.dart: connect, `session.hello` with the persisted cursor, command/reply correlation by `id` with a 10s timeout (contract §5), an event stream, a phase stream, exponential backoff 1→30s with ±20% jitter reset ON HELLO (research R4), and a 25s keepalive ping; unit tests in test/data/remote/socket/ over a fake channel covering correlation, timeout, backoff growth and reset, and phase transitions
- [ ] T007 Expose the phase to the domain: lib/domain/service/session_phase_service.dart + its data-layer implementation reading the socket's phase stream; register in DI for `[Environment.dev]` with an always-`live` stub for `[Environment.prod, Environment.test]` so existing tests are unaffected (mirrors the ConnectivityService env split)
- [ ] T008 Add the data-source epoch to the sync store (research R8, FR-009): `getEpoch`/`setEpoch` on lib/domain/repository/sync/sync_repository.dart + impl + SyncDao field; on boot compare the current source identity (`mock` vs `live:<apiUrl>`) and, when it differs, wipe the chats store, the messages store and the cursor exactly once, then persist the new epoch; tests in test/data/repository/sync/ proving the wipe fires once and not on an unchanged epoch
- [ ] T009 Wire the server address: add `app.apiUrl` to config/stage.json, read it in AppConfig/AppFlavor, and derive the socket URL from it (`http→ws`, `https→wss`, path `/ws`, research R12); unit test the derivation
- [ ] T010 Run `make gate` and fix all fallout; commit the foundation

**Checkpoint**: транспорт подключается к живому серверу и переживает обрыв; продуктовые экраны всё ещё на моках.

## Phase 3: User Story 1 — Данные приходят с сервера (Priority: P1) 🎯 MVP

**Goal**: список чатов и история треда приходят с `noxd`, а не из мок-генераторов.

**Independent Test**: создать чат сторонним клиентом → он виден в приложении; открыть → видна серверная история; прокрутка вверх приносит более старые сообщения.

- [ ] T011 [US1] Grow the chat network boundary per research R6: add `createChat`, `renameChat`, `isNameAvailable` to lib/data/remote/datasource/chat_remote_data_source.dart and move the current local behaviour into lib/data/remote/datasource/mock/mock_chat_remote_data_source.dart so the mock path keeps working unchanged
- [ ] T012 [US1] Reshape the message boundary per research R7: `sendMessage({chatId, clientMessageId, text, attachment})` in lib/data/remote/datasource/message_remote_data_source.dart (drop authorId/authorLabel), update the mock and MessageRepositoryImpl which now mints the `client_message_id`
- [ ] T013 [P] [US1] Implement lib/data/remote/datasource/real/real_chat_remote_data_source.dart over the socket (`chats.list`, `chat.create`, `chat.rename`, `chat.nameAvailable`), returning `ResponseEntity` so the 025 error path is reused verbatim; tests over a fake socket asserting the reply wrapper `{chat: …}` is unwrapped and `name_taken` surfaces as the typed exception
- [ ] T014 [P] [US1] Implement lib/data/remote/datasource/real/real_message_remote_data_source.dart over the socket (`messages.list`, `message.send`), unwrapping `{message: …}`; tests over a fake socket incl. a clamped `limit`
- [ ] T015 [US1] Flip the DI bindings three-step per specs/016-remote-datasource-seam/contracts/di-binding.md: register `Real*` for `[Environment.dev]`, narrow the mocks to `[Environment.prod, Environment.test]`, run `make generate`; update test/di/seam_binding_test.dart to assert the split
- [ ] T016 [US1] Rework `ChatThreadBloc._refreshMessages` to read only the newest batch instead of the whole loaded span (research R9): the loaded history cannot change under contract v0, and asking for more than 100 would silently truncate; update chat_thread_bloc tests
- [ ] T017 [US1] Run `make gate` AND `make golden-verify` — 216 baselines must pass unregenerated (SC-005) — then validate US1 live per quickstart.md; commit

**Checkpoint**: приложение читает живой сервер; отправка ещё не проверена.

## Phase 4: User Story 2 — Сообщение уходит и приходит второму клиенту (Priority: P2)

**Goal**: отправленное сообщение возвращается эхом и появляется у второго клиента; входящее появляется само.

**Independent Test**: два клиента на одном `noxd` — отправка с любого видна другому; строка чата в списке обновляет превью и порядок.

- [ ] T018 [US2] Implement lib/data/sync/sync_service.dart (research R10): subscribe to the socket's event stream, apply `chat.created`/`chat.updated` through ChatDao and `message.new` through MessageDao, advance the cursor ONLY after a successful write (FR-008), and drop any event whose `seq <= cursor` (dedup, FR-007); register it in DI for `[Environment.dev]` and start it with the connection
- [ ] T019 [US2] Handle an event for a chat that is not in the local store (spec edge case): fetch the chat row on demand or persist from the event payload, so an incoming message never lands orphaned; test it
- [ ] T020 [US2] Persist the identity from the hello reply into the session on every connect (FR-012, research R11) so the existing `watchLabel` channel repaints both account avatars; test that a label changed server-side propagates
- [ ] T021 [US2] Run `make gate` + `make golden-verify`, then validate US2 live per quickstart.md with two clients; commit

**Checkpoint**: живой обмен работает — это и есть результат, ради которого владелец выбрал вертикаль.

## Phase 5: User Story 3 — Связь рвётся и восстанавливается (Priority: P3)

**Goal**: обрыв переживается, пропущенное догоняется ровно один раз.

**Independent Test**: оборвать сервер, дослать сообщения вторым клиентом, поднять сервер — приложение догоняет без дублей и пропусков.

- [ ] T022 [US3] Route the three existing connectivity consumers through the session phase instead of raw device connectivity (FR-005, research R3): `online = phase == live` at the seam, so ChatsListBloc/ChatThreadBloc/ChatCardBloc keep their `connectivityChanged(bool)` event and NO new UI state appears; update their tests
- [ ] T023 [US3] Flush the pending send queue on entering `live` rather than on the device coming online, and verify a send issued while disconnected leaves with the SAME `client_message_id` so the server dedupes it (FR-007, contract idempotency)
- [ ] T024 [US3] Prove the catch-up rule end to end in a test over the fake socket: replay delivers events below the hello cursor, the phase flips to `live` at `seq >= cursor`, duplicates across the replay/live boundary are dropped, and the cursor never moves backwards
- [ ] T025 [US3] Run `make gate` + `make golden-verify`, then validate US3 live per quickstart.md (kill the server mid-session, send from the second client, restart); commit

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T026 [P] Update the blueprints per Principle III: 04-data-layer.md and 14-networking-and-auth.md move from "REST is the main limb" to the real split (WS envelope for commands, REST only for blob bytes), and document the transport, session phases and the event→DAO application path
- [ ] T027 [P] Update docs/client-backend/roadmap-client-track.md (026 status + journal row) and the CLAUDE.md implementation notes: the data layer is no longer mock-only on the dev flavor
- [ ] T028 Full local gate: `make gate` + `make golden-verify`, then the complete owner walkthrough from quickstart.md (all three stories against a live `noxd`); commit

## Dependencies & Execution Order

```text
Setup:        T001 → T002
Foundational: T003 [P] ∥ T004 [P] → T005 → T006 → T007 → T008 → T009 → T010
US1 (P1):     T011 → T012 → (T013 [P] ∥ T014 [P]) → T015 → T016 → T017
US2 (P2):     T018 → T019 → T020 → T021          (после US1: нужны реальные датасорсы)
US3 (P3):     T022 → T023 → T024 → T025          (после US2: догон проверяется на реальных событиях)
Polish:       T026 [P] ∥ T027 [P] → T028
```

### Parallel Opportunities

- T003 и T004 — разные файлы, независимы.
- T013 и T014 — два датасорса, разные файлы, общий уже готовый транспорт.
- T026 и T027 — разные документы.

## Implementation Strategy

**MVP** — Setup + Foundational + US1 (T001–T017): приложение читает живой сервер. Уже на этом месте владелец видит серверные данные на экране.

Затем US2 (T018–T021) — собственно обмен, ради которого фаза и выбрана, и US3 (T022–T025) — устойчивость.

Коммит на историю; `make gate` перед каждым коммитом, `make golden-verify` на чек-пойнтах T017/T021/T025/T028. Живая проверка по `quickstart.md` — на тех же чек-пойнтах, потому что автоматический набор идёт на моках и живую вертикаль не покрывает.
