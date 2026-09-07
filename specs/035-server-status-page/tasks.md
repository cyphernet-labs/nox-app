# Tasks: Стартовая и статусная страница сервера

**Input**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/)

**Tests**: обязательны. CI на паузе, локальный гейт — единственное место, где ловится регрессия, а фаза трогает то, чем забирают сервер.

**Organization**: по пользовательским историям. US1 и US2 — две ветки одной страницы и делят слушатель; US3 (приватность) проверяется поверх обеих; US4 — документация.

## Phase 1: Конфигурация и зависимость

- [X] T001 Add the QR encoder to `client_backend/go.mod` and record the justification in `client_backend/CLAUDE.md` — a pure-Go encoder with no dependencies of its own, chosen because encoding a QR is a whole capability rather than a convenience
- [X] T002 Add `StatusAddr` to `client_backend/internal/config/config.go`: flag `-status-addr`, env, default `127.0.0.1:8081`, empty meaning "no page at all"
- [X] T003 Refuse a non-loopback `-status-addr` at parse time in `client_backend/internal/config/config.go` — the flag exists to move the port, not to put the page on a network
- [X] T004 [P] Config tests in `client_backend/internal/config/config_test.go`: the default, the empty value, a moved port, and a refused `0.0.0.0`

**Checkpoint**: конфигурация знает про страницу; ничего ещё не слушает.

---

## Phase 2: Foundational — данные страницы

**⚠️ Блокирует обе ветки страницы.**

- [X] T005 Add `Counts` and `CountEverything` to `client_backend/internal/store/stats.go` — people, devices, chats and messages in one read, and NOTHING that carries a name, a title, a body or a key
- [X] T006 [P] Store test in `client_backend/internal/store/stats_test.go`: counts on an empty store are zeros rather than absent, and the query list is asserted to touch no column that names anybody
- [X] T007 Add `buildVersion()` to `client_backend/internal/server/status.go` reading `runtime/debug.ReadBuildInfo` — revision, build time and the dirty flag, and an honest "unknown" when built without git
- [X] T008 Add `machineStatus` and its collector to `client_backend/internal/server/status.go`: ownership, journal id, schema version, counts, database file size, version, uptime, startup warnings
- [X] T009 Carry the schema version and the startup warnings from `Run` into the `Server` in `client_backend/internal/server/server.go`, so the page can show what only the terminal saw

**Checkpoint**: состояние машины собирается; страницы ещё нет.

---

## Phase 3: User Story 1 — забрать сервер по QR (Priority: P1) 🎯 MVP

**Goal**: свежий сервер забирается сканированием кода с экрана.

**Independent Test**: свежая база, браузер на той же машине, телефон рядом — захват без единого перепечатанного символа.

- [X] T010 [US1] Mint the claim link ONCE per process and hold it on the `Server` in `client_backend/internal/server/server.go`: seeded by what `announceClaim` already built, minted lazily if the state turns to "needs a link" mid-run, never per request — a claim token has no expiry, so one per page load would be an unrevocable door per browser refresh
- [X] T011 [US1] Bring up the loopback listener in `client_backend/internal/server/server.go`, in the same group as the main one and stopped in the same order — before the database closes (invariant 9)
- [X] T012 [US1] Render the unclaimed page in `client_backend/internal/server/status_page.go`: the QR, the same link as text, and a sentence saying what it is — somebody installing a server for the first time is not required to know the word "claim"
- [X] T013 [US1] Render the QR as inline SVG in `client_backend/internal/server/status_qr.go`, large and high-contrast, and readable in a browser's dark theme
- [X] T013a [US1] Resolve a DIALLABLE address for the QR in `client_backend/internal/server/status.go`: the bind address when it is concrete, otherwise the first non-loopback interface address. `listenAddress` falls back to loopback under a wildcard — right for the startup line, read on the machine, and useless for the phone this page exists to serve
- [X] T013b [US1] When no non-loopback address exists, show no QR and say so, pointing at the startup output — a code nothing can dial is worse than none
- [X] T013c [P] [US1] Test in `client_backend/internal/server/status_test.go`: the QR's address is non-loopback under a wildcard bind, and equals the bind address when it is concrete; the TOKEN matches the one the startup announcement used
- [X] T014 [US1] Decide between the THREE pages on the same `OwnershipState` the startup announcement reads, fresh on every request: needs-a-link, claimed, and a store with people but no owner
- [X] T014a [US1] Render the ownerless-store page in `client_backend/internal/server/status_page.go`: no link, because `Pair` refuses a claim there and a link would be an instruction that cannot be followed — say what the startup log says, that this machine has no owner
- [X] T014b [P] [US1] Test in `client_backend/internal/server/status_test.go`: a store with people and no owner serves neither a link nor a QR
- [X] T015 [US1] Print the page's address at startup next to the link in `client_backend/internal/server/server.go` — otherwise nobody learns it exists
- [X] T016 [P] [US1] Server test in `client_backend/internal/server/status_test.go`: an unclaimed server serves the link and the QR, and the link is byte-identical to the one the startup announcement built
- [X] T017 [P] [US1] Server test: the page is NOT reachable on the main listener under any path

**Checkpoint**: сервер забирается с экрана.

---

## Phase 4: User Story 2 — состояние машины (Priority: P1)

**Goal**: страница рассказывает о машине то, что нужно тому, кто её держит.

**Independent Test**: забранный сервер показывает девять сведений и ни одного имени.

- [X] T018 [US2] Render the claimed page in `client_backend/internal/server/status_page.go`: version and build, uptime, schema version, claimed, journal id, the four counters, database size, and any startup warning
- [X] T019 [US2] Refresh the claimed page every ten seconds, and NEVER the unclaimed one — redrawing a code under the camera reading it breaks the one scenario the page exists for
- [X] T020 [P] [US2] Server test in `client_backend/internal/server/status_test.go`: a claimed server shows every item of FR-009 and carries no link
- [X] T021 [P] [US2] Server test: an owner who lost every device sees the link again — "claimed" for the page means what it means for the server, that the owner can still get in

**Checkpoint**: обе ветки работают.

---

## Phase 5: User Story 3 — ничего лишнего на экране (Priority: P1)

**Goal**: страницу можно показать через плечо.

**Independent Test**: сервер с людьми и перепиской — на странице ни одного имени.

- [X] T022 [US3] Server test in `client_backend/internal/server/status_test.go`: against a store holding a named person, a named chat and a message, the rendered page contains none of those strings, no device public key and no token
- [X] T023 [US3] Server test: a claimed server's page carries the claim link nowhere — not as a link, not as a QR, not in the markup
- [X] T023a [P] Regression test in `client_backend/internal/server/health_test.go`: `GET /health` answers exactly what it answered — OS services and the tunnel read it, and a page for people must not change a machine's answer (FR-013)
- [X] T023b [P] Test in `client_backend/internal/server/status_test.go`: the status listener's resolved address is loopback, so "unreachable from the network" is asserted rather than assumed (SC-002)

**Checkpoint**: Принцип I проверен, а не заявлен.

---

## Phase 6: User Story 4 — машина без экрана (Priority: P2)

**Goal**: случай назван прямо, а не оставлен выясняться.

- [X] T024 [P] [US4] Say in `docs/client-backend/roadmap-stage2.md` and in the deployment notes that a headless server cannot use the page, and name the two ways round it: the startup output and an SSH port forward
- [X] T025 [P] [US4] Assert in `client_backend/internal/server/status_test.go` that the startup announcement still prints the claim link — the page does not replace it

---

## Phase 7: Polish

- [X] T026 [P] Record in `docs/client-backend/protocol/contract-draft.md` §1 that the page is NOT an interface: no fixed format, not to be parsed, `/health` remains the machine answer
- [X] T027 [P] Record the phase's invariants in `client_backend/CLAUDE.md`: the separate loopback listener, one claim token per process, and the ownership predicate shared with the announcement
- [X] T028 [P] Mark 035 ☑ in `docs/client-backend/roadmap-stage2.md`
- [X] T029 Run `gofmt -l .`, `go vet ./...` and `go test -race ./...`
- [X] T030 Confirm `make gate` and `make golden-verify` are unchanged — this phase must not touch the client at all
- [ ] T031 Walk [quickstart.md](./quickstart.md) against a real `noxd`

---

## Dependencies & Execution Order

- **Phase 1** первым: без флага слушателю негде подняться.
- **Phase 2** блокирует обе ветки страницы.
- **US1** — MVP. **US2** садится на тот же слушатель и тот же сбор.
- **US3** проверяет обе и без них бессмысленна.
- **US4** — документация, параллельна всему.
- **Polish** после всех.

### Parallel Opportunities

- T004, T006 — разные файлы тестов.
- T016, T017, T020, T021 — независимые тесты одного файла, пишутся вместе.
- T024, T026, T027, T028 — четыре разных документа.

## Notes

- Кириллица не появляется ни в коде, ни в комментариях, ни в сообщениях коммитов.
- Текст страницы — английский, как весь UI.
- Клиент не трогается: любое изменение в `lib/` в этой фазе — ошибка.
