# Tasks: Client-сервер — bootstrap этапа 1

**Input**: Design documents from `/specs/022-client-backend-bootstrap/` — [plan.md](plan.md), [spec.md](spec.md), [data-model.md](data-model.md), [research.md](research.md), [contracts/README.md](contracts/README.md), [quickstart.md](quickstart.md)

**Tests**: включены — `go test -race` обязателен конституцией (Go-гейт) и инвариантами `client_backend/CLAUDE.md`; каждая история закрывается интеграционным тестом + ручным смоуком из quickstart.

**Организация**: фазы по историям спеки; каждая история — независимо тестируемый инкремент. Все пути — от корня репозитория. Перед началом: прочитать `client_backend/CLAUDE.md`, скиллы `/go-style` и `/ws-rest-patterns`; провод — только по `docs/client-backend/protocol/contract-draft.md` (срез — [contracts/README.md](contracts/README.md)).

## Phase 1: Setup

- [ ] T001 Initialize the Go module in client_backend/go.mod (module nox.app/client-backend, go 1.27) and pin the three direct dependencies (github.com/coder/websocket, modernc.org/sqlite, golang.org/x/sync); create the internal/{config,db,store,hub,protocol,server} directory skeleton with doc.go placeholders per plan.md structure

## Phase 2: Foundational (blocking prerequisites)

- [ ] T002 Create the initial schema migration in client_backend/migrations/001_init.sql: STRICT tables chats / messages / events exactly per data-model.md (UNIQUE lower(name), UNIQUE client_message_id, events AUTOINCREMENT seq, index (chat_id, seq))
- [ ] T003 [P] Implement configuration in client_backend/internal/config/config.go: flags -addr (default 127.0.0.1:8080) and -db with NOX_ADDR/NOX_DB env overrides, limits constants from contract §3 example, startup validation; table test in config_test.go
- [ ] T004 Implement database bootstrap in client_backend/internal/db/db.go and migrate.go: two pools (reader; writer SetMaxOpenConns(1) + _txlock=immediate), fixed pragmas per CLAUDE.md invariant 13, embed.FS migration runner via PRAGMA user_version; tests in db_test.go (migrate from zero in t.TempDir, pragma verification, never :memory:)
- [ ] T005 [P] Implement envelope v0 in client_backend/internal/protocol/frames.go and errors.go: srv/command/reply/event frame types with json tags per contract §2, two-phase decode via json.RawMessage, error-code constants of the 022 slice; marshal/unmarshal table tests in frames_test.go
- [ ] T006 Implement store foundation in client_backend/internal/store/store.go: Store with both pool handles, write-transaction helper enforcing the transactional outbox (mutation + events row in one BEGIN IMMEDIATE, event payload built at write time), EventsSince(seq) reader; tests in store_test.go for atomicity (failed tx leaves no event) and EventsSince ordering
- [ ] T007 [P] Implement the hub in client_backend/internal/hub/hub.go: Run goroutine owning the subscriber map, register/unregister/broadcast channels, per-client buffered send channel (16), overflow drop policy signalling the connection to close; tests in hub_test.go including slow-subscriber drop and no-mutex ownership (race)
- [ ] T008 Implement server wiring in client_backend/internal/server/server.go, ws.go, client.go and health.go: ServeMux with GET /health and GET /ws, websocket Accept + SetReadLimit(max_frame_bytes), srv greeting frame with random challenge, single read loop + write pump per ws-rest-patterns sketches, connection registry, command dispatch table returning invalid_request for unknown cmd and rejecting any command before session.hello
- [ ] T009 Implement process lifecycle in client_backend/main.go: flags → config → db → store → hub → http server via signal.NotifyContext + errgroup; ordered shutdown per CLAUDE.md invariant 9 (HTTP drain → registry Close(StatusGoingAway) via RegisterOnShutdown → hub stop → db close); smoke assertion in server_test.go that /health serves 200

**Checkpoint**: процесс собирается, стартует, `/health` отвечает, WS принимает соединение и шлёт приветствие; команд ещё нет.

## Phase 3: User Story 1 — обмен вживую (P1) 🎯 MVP

**Goal**: два websocat-клиента обмениваются сообщениями через chat.create / message.send с живыми событиями.

**Independent Test**: quickstart.md смоук A + негативные проверки; интеграционные тесты истории.

- [ ] T010 [US1] Implement session.hello (no-replay path) in client_backend/internal/server/handlers.go: schema check (unsupported_schema), optional label field with User<n> fallback per contract §3 stage-1 field, ignored device_key/signature, limits + identity reply, hub subscribe, cursor from store, duplicate-hello and command-before-hello rejection
- [ ] T011 [US1] Implement chat.create in client_backend/internal/store/store.go (CreateChat: name trim/empty/64 validation upstream, case-insensitive uniqueness via lower(name), created_by_label, chat.created event payload) and wire the handler with name_taken mapping in client_backend/internal/server/handlers.go
- [ ] T012 [US1] Implement message.send in client_backend/internal/store/store.go (SendMessage: idempotency by UNIQUE client_message_id returning the original message on conflict, seq from the event row, last_activity_at + preview fold ≤120 chars single line per contract §6) and the handler with payload_too_large preflight against config limits in client_backend/internal/server/handlers.go
- [ ] T013 [US1] Add story-1 integration tests in client_backend/internal/server/integration_test.go: httptest + websocket.Dial two clients — greeting-first, hello echo with label, chat.create echo + chat.created event on the second client, message.send echo + message.new with monotonic seq and client_message_id, duplicate send returns identical echo with no second event, name_taken case-insensitive, unknown cmd → invalid_request
- [ ] T014 [US1] Write client_backend/README.md (FR-011): build/run commands, flags/env table, full smoke A transcript and negative checks copied from specs/022-client-backend-bootstrap/quickstart.md, kept in sync with it

**Checkpoint**: смоук A проходит вручную — MVP фичи достигнут.

## Phase 4: User Story 2 — переподключение и догон (P2)

**Goal**: клиент с `since` получает пропущенное без потерь, затем live; правило «догнан».

**Independent Test**: quickstart.md смоук B; replay-тесты.

- [ ] T015 [US2] Implement the replay path in client_backend/internal/server/handlers.go: subscribe → hello reply → EventsSince(since) replayed in seq order → live interleave per ws-rest-patterns §4; omitted since = no replay; since > cursor edge (empty replay, slog warning per spec edge case)
- [ ] T016 [US2] Add story-2 integration tests in client_backend/internal/server/replay_test.go: kill-reconnect-catchup flow (N events missed, all delivered in order), duplicate-at-boundary tolerance (live event during replay), since==cursor immediate caught-up, since>cursor deterministic behavior, replay repeatability (same since twice → same events)
- [ ] T017 [US2] Extend client_backend/README.md with the smoke B section (reconnect with since, caught-up rule seq ≥ cursor) in sync with quickstart.md

**Checkpoint**: смоук B проходит; курсорная синхронизация доказана.

## Phase 5: User Story 3 — живучесть и остановка (P3)

**Goal**: медленный клиент не мешает остальным; ping держит соединения; Ctrl+C завершает всё аккуратно; данные переживают рестарты.

**Independent Test**: quickstart.md смоук C; тесты drop/shutdown/restart.

- [ ] T018 [US3] Wire keepalive and slow-client closure in client_backend/internal/server/client.go: ping ticker ~25s in the write pump, hub drop signal → Close(StatusPolicyViolation, "slow consumer"), read-limit violation closes the connection
- [ ] T019 [US3] Add story-3 tests in client_backend/internal/server/lifecycle_test.go: slow client dropped with policy-violation code while the second client keeps receiving (latency assertion), server Shutdown delivers StatusGoingAway to open connections and exits within timeout, restart cycle test (start → write → stop → start with same db → data intact, replay still correct) with goroutine leak check
- [ ] T020 [US3] Extend client_backend/README.md with the smoke C section (slow client, Ctrl+C semantics, restart) in sync with quickstart.md

**Checkpoint**: смоук C проходит; все три истории закрыты.

## Final Phase: Polish & cross-cutting

- [ ] T021 [P] Audit logging against Principle I in client_backend/internal: slog never logs message bodies, labels or frame payloads — only cmd names, error codes, seq, durations; add a request-log middleware for REST and connection-scoped logger fields
- [ ] T022 [P] Run the full local gate and fix findings: gofmt -l . empty, go vet ./..., go test -race ./... green in client_backend/; verify the 13 CLAUDE.md invariants against the final code and reconcile any drift in the same change-set
- [ ] T023 Validate quickstart end-to-end as the owner would (fresh build, all three smokes + negative checks, ≤10 min per SC-001) and reconcile README/quickstart wording; then mark phase 022 done in docs/client-backend/roadmap-stage1.md (status + journal row)

## Dependencies

```
Setup:        T001
Foundational: T002 → T004 → T006 ─┐          T003 [P], T005 [P], T007 [P] — параллельно
                                  ├→ T008 → T009
US1 (P1):     T010 → T011 → T012 → T013 → T14  (после T009)
US2 (P2):     T015 → T016 → T017               (после US1: replay поверх живых событий)
US3 (P3):     T018 → T019 → T020               (после T009; независим от US2, но смоук C использует данные US1)
Polish:       T021 [P], T022 [P] → T023        (после всех историй)
```

Истории независимо тестируемы: US1 — MVP сам по себе; US2 добавляет replay, не трогая команды; US3 — только lifecycle-код.

## Parallel execution examples

- Phase 2: T003 (config) ∥ T005 (protocol) ∥ T007 (hub) — разные пакеты без взаимных импортов; T004→T006 — последовательно (store зависит от db).
- US1: T011 и T012 трогают общие файлы (store.go, handlers.go) — последовательно; T014 (README) можно писать параллельно с T013.
- Polish: T021 ∥ T022.

## Implementation strategy

**MVP first**: Phase 1 → 2 → 3 (T001–T014) даёт демонстрируемый продукт — смоук A руками владельца. Остановка здесь уже ценна.

**Incremental delivery**: US2 и US3 — независимые приращения; каждая фаза заканчивается зелёным Go-гейтом и ручным смоуком своей истории. Коммит на фазу (или чаще), `--no-ff` мерж ветки в develop — после T023.
