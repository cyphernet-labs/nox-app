# Tasks: Приглашение нового человека в круг

**Input**: Design documents from `/specs/034-invite-person/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/)

**Tests**: тесты обязательны. Проект держит локальный гейт вместо CI (`make gate`, `make golden-verify`, `go test -race ./...`), и фаза трогает путь входа на сервер — единственное место, где ошибка означает «впустили не того».

**Organization**: задачи сгруппированы по пользовательским историям. US1–US3 все P1 и делят один путь кода: US1 — счастливый исход, US2 — право выпускать, US3 — то, что происходит без подтверждения. Проверяются они независимо, но выпускать по отдельности нечего: круг, в который можно войти без спроса, — это не половина фазы, а её отсутствие.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: можно вести параллельно (разные файлы, нет зависимостей)
- **[Story]**: к какой истории относится (US1, US2, US3, US4)

---

## Phase 1: Контракт (Принцип VII — провод правится первым)

**Purpose**: ни одна строка кода не пишется раньше провода. Обе стороны потом сверяются с одним текстом, а не друг с другом.

- [ ] T001 [P] Add `not_owner`, `pair_declined` and `pair_timeout` to the error table in `docs/client-backend/protocol/contract-draft.md` §2.1
- [ ] T002 Add `status` to the `pair` reply (`paired` with `identity`, `pending` with `request_id` and `expires_at`) and the re-presentation table in `docs/client-backend/protocol/contract-draft.md` §8A
- [ ] T003 [P] Document `person.invite` (owner only, 24 hours) in `docs/client-backend/protocol/contract-draft.md` §8A
- [ ] T004 [P] Document `person.list` (id, label, owner — no devices, no keys) in `docs/client-backend/protocol/contract-draft.md` §8A
- [ ] T005 [P] Document `person.confirm` (request_id, approve) in `docs/client-backend/protocol/contract-draft.md` §8A
- [ ] T006 Document the `person.pairRequested` and `person.pairResolved` events (seq 0, off-journal) in `docs/client-backend/protocol/contract-draft.md` §8A
- [ ] T007 Replace the two now-stale notes in `docs/client-backend/protocol/contract-draft.md` §8A — "`invite-user` заблокирован Q15" under `device.invite`, and "вопрос возвращается" under `device.list` — and add the deadlines table

**Checkpoint**: контракт описывает фазу целиком; дальше код только исполняет его.

---

## Phase 2: Foundational (блокирует все истории)

**Purpose**: схема, коды и типы, без которых ни одна ветка не компилируется.

**⚠️ CRITICAL**: до конца этой фазы работа по историям не начинается.

- [ ] T008 Extend `pair_tokens` in `client_backend/migrations/001_init.sql`: `invite_user` in the kind CHECK, plus `request_id TEXT UNIQUE`, `awaiting_platform TEXT`, `awaiting_until INTEGER`, `outcome TEXT CHECK`, and `idx_pair_tokens_pending` on `(outcome, awaiting_until)`
- [ ] T009 [P] Add `ErrNotOwner`, `ErrPairDeclined` and `ErrPairTimeout` wire codes to `client_backend/internal/protocol/errors.go`
- [ ] T010 [P] Add `CmdPersonInvite`, `CmdPersonList`, `CmdPersonConfirm`, `EventPairRequested` and `EventPairResolved` to `client_backend/internal/protocol/frames.go`
- [ ] T011 Add `TokenInviteUser`, `PersonInviteTTLSeconds` (86400), `ApprovalWindowSeconds` (300) and `IssuePersonInvite` to `client_backend/internal/store/pairing.go`
- [ ] T012 Introduce `store.PairResult{Identity, Pending, RequestID}` in `client_backend/internal/store/pairing.go` and change `Pair` to return it, updating every call site and test
- [ ] T013 [P] Create `client_backend/internal/store/approval.go` with `PendingRequest`, the three sentinel errors and `randomRequestID`

**Checkpoint**: сервер собирается и все прежние тесты зелены на новой сигнатуре.

---

## Phase 3: User Story 1 — владелец зовёт человека, и тот входит (Priority: P1) 🎯 MVP

**Goal**: приглашение человека доходит до конца: предъявление ждёт, владелец подтверждает, появляется вторая личность со своим именем и своим списком устройств.

**Independent Test**: два клиента против одного `noxd`. Второй входит по приглашению, называется, пишет — и на первом сообщение показано чужим, с именем автора.

### Сервер

- [ ] T014 [US1] Add the `invite_user` branch to `Pair` in `client_backend/internal/store/pairing.go`: refuse a device key already bound to somebody else FIRST, then record the pending request (`request_id`, `used_by`, `awaiting_platform`, `awaiting_until`) and return `PairResult{Pending: true}`
- [ ] T015 [US1] Implement the approve path of `ConfirmPair` in `client_backend/internal/store/approval.go`: one transaction creating the person, inserting the device, writing `paired_user_id`/`created_person` and setting `outcome = 'approved'`
- [ ] T016 [US1] Teach `handlePair` in `client_backend/internal/server/pairing.go` to answer `status: "paired"` or `status: "pending"`
- [ ] T017 [US1] Implement `handlePersonInvite` in `client_backend/internal/server/pairing.go`, building the link the way `device.invite` does
- [ ] T018 [US1] Implement `handlePersonConfirm` in `client_backend/internal/server/pairing.go`
- [ ] T019 [US1] Route `person.invite`, `person.list` and `person.confirm` in `client_backend/internal/server/handlers.go`
- [ ] T020 [US1] Add `notifyPairRequested` and `notifyPairResolved` to `client_backend/internal/server/server.go`, delivering to the waiting connection and to every live connection of the owner
- [ ] T021 [US1] Re-send every outstanding request to the owner right after a successful greeting, in `client_backend/internal/server/handlers.go`
- [ ] T022 [P] [US1] Store tests in `client_backend/internal/store/approval_test.go`: pending is recorded, approval creates a person, the new person owns nothing, the token records its outcome
- [ ] T023 [US1] Server test in `client_backend/internal/server/pairing_test.go`: present → pending reply → confirm → resolved event carries the identity with `created: true` and `owner: false`

### Клиент

- [ ] T024 [P] [US1] Add `personPairRequested` and `personPairResolved` to `lib/data/remote/socket/server_frame.dart`
- [ ] T025 [US1] Parse the `pair` reply's `status` and add `invitePerson`, `listPeople` and `confirmPair` to `lib/data/remote/socket/nox_socket_client.dart`
- [ ] T026 [P] [US1] Create the `PairOutcome` sealed union (`paired` · `declined` · `timedOut` · `refused`) in `lib/domain/model/session/pair_outcome.dart`
- [ ] T027 [US1] Make `LiveIdentityHandshake.pair` in `lib/data/sync/live_identity_handshake.dart` wait for `person.pairResolved` on a pending reply, owning its own timer the way `greet()` does
- [ ] T028 [US1] Return the four outcomes from sign-in in `lib/data/repository/app/auth_repository_impl.dart`
- [ ] T029 [P] [US1] Create `lib/data/sync/pair_request_service.dart` — a replaying stream of open confirmation requests
- [ ] T030 [P] [US1] Create `PersonModel` in `lib/domain/model/person/person_model.dart` and `PairRequest` in `lib/domain/model/person/pair_request.dart`
- [ ] T031 [P] [US1] Declare `PersonRepository` in `lib/domain/repository/person/person_repository.dart`
- [ ] T032 [US1] Implement `PersonRepositoryImpl` in `lib/data/repository/person/person_repository_impl.dart` (`env: [Environment.dev]`, socket-only, no cache — the same reasoning as `DeviceRepositoryImpl`)
- [ ] T033 [US1] Create the `PeopleBloc` with its Freezed event/state in `lib/presentation/pages/people_page/bloc/`
- [ ] T034 [US1] Build `PeopleBody` and `PeoplePage` in `lib/presentation/pages/people_page/`, reusing `AppSettingsGroupWidget` and the QR/link invite card of 7.3
- [ ] T035 [US1] Add the owner-only `People` row to `lib/presentation/pages/settings_root_page/settings_root_page.dart` and wire it into the desktop detail pane
- [ ] T036 [US1] Build the confirmation surface in `lib/presentation/pages/pair_request_page/` — `route()` when narrow, `showAsDialog` when wide
- [ ] T037 [US1] Subscribe to `PairRequestService` in `lib/presentation/widgets/app_root.dart` so the question reaches the owner wherever they are
- [ ] T038 [P] [US1] Add the microcopy for both surfaces to `lib/l10n/app_en.arb` and `lib/l10n/app_uk.arb` (identical key sets)
- [ ] T039 [P] [US1] Widget tests for both surfaces under `test/presentation/pages/people_page/` and `test/presentation/pages/pair_request_page/`
- [ ] T040 [US1] Goldens for both surfaces: mobile via `goldenTest`, desktop via `goldenTestDesktop`

**Checkpoint**: приглашение проходит путь целиком; второй человек существует и отличим от первого.

---

## Phase 4: User Story 2 — приглашать вправе только владелец (Priority: P1)

**Goal**: решение Q15 наконец что-то запрещает.

**Independent Test**: приглашённый клиент просит приглашение и получает отказ, отличимый от «токен недействителен»; владелец на том же сервере получает приглашение.

- [ ] T041 [US2] Refuse `IssuePersonInvite` with `ErrNotOwner` when the caller does not own the server, in `client_backend/internal/store/pairing.go`
- [ ] T042 [US2] Map `ErrNotOwner` onto the `not_owner` code in `handlePersonInvite` and `handlePersonConfirm` in `client_backend/internal/server/pairing.go`
- [ ] T043 [P] [US2] Server test in `client_backend/internal/server/pairing_test.go`: a non-owner is refused with `not_owner`, distinct from `invalid_token` and `internal`; the owner succeeds on the same server
- [ ] T044 [P] [US2] Widget test in `test/presentation/pages/settings_root_page/`: the `People` row is absent for a non-owner and for "the server did not say" alike

**Checkpoint**: право выпускать проверяется на сервере и не предлагается в приложении.

---

## Phase 5: User Story 3 — приглашение не срабатывает без владельца (Priority: P1)

**Goal**: перехваченная или пересланная ссылка бесполезна сама по себе.

**Independent Test**: приглашение предъявлено, владелец отклоняет — предъявивший получает отличимый отказ и не попадает внутрь; личность не заведена.

- [ ] T045 [US3] Implement the decline path of `ConfirmPair` in `client_backend/internal/store/approval.go`
- [ ] T046 [US3] Implement `ExpirePendingPairs` in `client_backend/internal/store/approval.go` and the lazy expiry check taken on re-presentation in `client_backend/internal/store/pairing.go`
- [ ] T047 [US3] Add `runPairSweeper` to `client_backend/internal/server/server.go`, in the same group as `runDispatcher`, pushing `person.pairResolved` for everything it expires
- [ ] T048 [US3] Answer a re-presentation from the recorded outcome in `client_backend/internal/store/pairing.go` — `pending` again, the identity, `ErrPairDeclined` or `ErrPairTimeout` — and `ErrTokenInvalid` for any other key
- [ ] T049 [US3] Map the two new sentinels onto `pair_declined` and `pair_timeout` in `client_backend/internal/server/pairing.go`
- [ ] T050 [P] [US3] Store tests in `client_backend/internal/store/approval_test.go`: decline, expiry, a pending request surviving a reopen of the store, re-presentation after each outcome, and a foreign key getting `invalid_token` in every case
- [ ] T051 [US3] Server test in `client_backend/internal/server/pairing_test.go`: the sweeper resolves both sides, and an answer from one owner device closes the question on the other
- [ ] T052 [US3] Show the four outcomes distinctly on the pairing screen in `lib/presentation/pages/login_page/` — "not usable", "expired", "the owner declined", "the owner did not answer"
- [ ] T053 [P] [US3] Bloc test for the four outcomes under `test/presentation/pages/login_page/bloc/`

**Checkpoint**: без владельца не входит никто, и четыре отказа ведут к четырём разным действиям.

---

## Phase 6: User Story 4 — в списке видно, чьи устройства (Priority: P3)

**Goal**: признак владения, отложенный из фазы 033, наконец несёт информацию.

**Independent Test**: на сервере два человека; в списке круга владелец отмечен, остальные — нет.

- [ ] T054 [P] [US4] Implement `ListPeople` in `client_backend/internal/store/people.go` — id, label and the owner mark, nothing else
- [ ] T055 [US4] Implement `handlePersonList` in `client_backend/internal/server/pairing.go`
- [ ] T056 [P] [US4] Store and server tests in `client_backend/internal/store/people_test.go`: exactly one person is marked owner, and the reply carries no devices, keys or counters
- [ ] T057 [US4] Render the circle in `lib/presentation/pages/people_page/people_body.dart`, reusing `AppOwnerBadgeWidget` extracted by feature 033
- [ ] T058 [P] [US4] Golden for the two-person list, mobile and desktop

**Checkpoint**: все истории работают независимо.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T059 [P] Record the phase's invariants in `client_backend/CLAUDE.md`: the outcome is recorded and never re-derived, the wait lives in the row, both events stay off the journal
- [ ] T060 [P] Add the `People` row and the new screens to `docs/design/spec/screens/settings-root.md` and a new screen doc under `docs/design/spec/screens/`
- [ ] T061 [P] Add both surfaces to the screen map in `docs/design/spec/top-level-screens.md`
- [ ] T062 [P] Reconcile `docs/blueprints/mobile/` with anything this phase changed about the live path
- [ ] T063 [P] Mark 034 ☑ in `docs/client-backend/roadmap-stage2.md`
- [ ] T064 Run `gofmt -l .`, `go vet ./...` and `go test -race ./...` in `client_backend/`
- [ ] T065 Run `make gate` and `make golden-verify`
- [ ] T066 Walk [quickstart.md](./quickstart.md) live against a real `noxd` with two clients

---

## Dependencies & Execution Order

### Phase Dependencies

- **Контракт (Phase 1)**: первым, без исключений (Принцип VII).
- **Foundational (Phase 2)**: зависит от Phase 1; блокирует все истории.
- **US1 (Phase 3)**: MVP. US2 и US3 садятся на её код.
- **US2 (Phase 4)**: технически независима от US1 — проверка права живёт на выпуске, — но проверять её нечем, пока приглашение человека не существует.
- **US3 (Phase 5)**: расширяет ветку US1 остальными исходами; отдельно от неё не собирается.
- **US4 (Phase 6)**: полностью независима после Phase 2. Может идти параллельно с US1.
- **Polish (Phase 7)**: после всех.

### Within Each User Story

- Схема → хранилище → провод → клиентские данные → экраны → тесты и голдены.
- Тест на отказ пишется вместе с отказом, а не после: отличимость отказов — требование, а не деталь.

### Parallel Opportunities

- T001, T003, T004, T005 — разные разделы контракта.
- T009, T010, T013 — разные файлы.
- US4 целиком параллельна US1: она не трогает ни `Pair`, ни ожидание.
- Клиентские T024, T026, T029, T030, T031, T038 — разные файлы, зависят только от контракта.

---

## Implementation Strategy

### MVP

Phase 1 → Phase 2 → Phase 3. Остановиться и проверить US1 вживую двумя клиентами: без этого нельзя быть уверенным, что второй человек вообще отличим от первого.

### Дальше

US3 сразу за US1 — она и есть половина решения Q15. US2 и US4 меньше и садятся поверх.

---

## Notes

- Коммит после каждой логической группы; `make gate` и `make golden-verify` перед каждым (CI на паузе).
- Кириллица не появляется ни в коде, ни в комментариях, ни в сообщениях коммитов.
- Микрокопия — английская, в обоих ARB одинаковым набором ключей.
- Каждое изменение UI проверяется на **обеих** ширинах, десктопный голден обязателен.
