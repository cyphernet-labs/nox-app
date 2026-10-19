# Tasks: Спаривание и устройства

**Input**: Design documents from `specs/046-pairing-devices/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md; 044 и 045 влиты в `security-rework`

**Tests**: обязательны: Go, Dart (блоки, виджеты), голдены обеих ширин для ожидания, диалога и 7.8, сквозной прогон на macOS.

**Organization**: контракт — первым; фундамент — схема и токены; затем истории. Go — по скиллам `go-style`, `ws-rest-patterns`, `add-command`, `migrations`; каждый коммит с кодом — после своего гейта.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [x] T001 Дельта §8A в `docs/client-backend/protocol/contract-draft.md` по `contracts/wire-pairing.md`: ссылка с машины (10 минут, живая одна), приглашение с ответом `pending`, `pair.cancel`, `device.approve`, события `pair.resolved`, `device.pairRequested`, `device.pairResolved` (`seq: 0`), отказы; «владелец» и claim без срока уходят

## Phase 2: Foundational

- [x] T002 Схема `client_backend/migrations/001_init.sql`: `pair_tokens` (`kind 'machine'`, `issuer_key`, `expires_at NOT NULL`), `pair_requests`, без `owner_user_id`/`claimed_at`; `internal/store/serverkey.go` без `OwnershipState` (состояние «устройств нет» — по числу устройств); тесты `internal/store/*_test.go`
- [x] T003 Токены в `client_backend/internal/store/pairing.go`: выпуск ссылки с машины (10 минут, гасит прежние непредъявленные в той же транзакции), приглашение с `issuer_key`, `Pair` по ссылке с машины — создать человека или присоединить к единственному; тесты (единственность, срок, повтор тем же ключом)

## Phase 3: User Story 1 — второе устройство по приглашению с подтверждением (P1) 🎯 MVP

- [x] T004 [US1] Запросы в `client_backend/internal/store/requests.go`: завести запрос по токену приглашения и ключу канала, найти тот же при повторе, закрыть (`allowed` — записать устройство, сжечь токен, одной транзакцией; `denied`, `expired`, `cancelled` — сжечь токен), выборка живых запросов выдавшего; тесты
- [x] T005 [US1] Сервер `client_backend/internal/server/{pairing,requests,ws,handlers}.go`, `internal/protocol/frames.go`: `pair` с приглашением → `pending`; `pair.cancel`; `device.approve`; события `pair.resolved` новому, `device.pairRequested`/`device.pairResolved` выдавшему (повтор живых после приветствия), `device.paired` остальным; ответ раньше рассылки; таймер сроков; отзыв выдавшего закрывает его запросы как `denied`; тесты (allow, deny, срок, cancel, повтор, второй ключ — `invalid_token`, отзыв выдавшего, SC-002: без `Allow` устройства нет)
- [x] T006 [P] [US1] `client_backend/cmd/smoke/main.go`: второе устройство ждёт и получает `allowed` после `device.approve` с первого
- [x] T007 [US1] Приложение, новое устройство: `lib/data/remote/socket/nox_socket_client.dart` (`pending`, `pair.cancel`, событие `pair.resolved`), `lib/data/sync/live_identity_handshake.dart` (ожидание исхода, повтор того же запроса после обрыва и перезапуска в пределах срока), `lib/data/repository/app/auth_repository_impl.dart` (исходы); тесты
- [x] T008 [US1] Экран ожидания в `lib/presentation/pages/connect_page/` (045): `Waiting for approval on your other device`, `Cancel`, `Your other device declined this request.`, срок; строки EN + UK; тесты блока; голдены ожидания и отказа — mobile + desktop
- [x] T009 [US1] Приложение, выдавшее устройство: служба `PairRequestService` (`lib/domain/service/pair_request_service.dart`, `lib/data/sync/pair_request_service_impl.dart`) — события `device.pairRequested`/`device.pairResolved`, `device.approve`; диалог `New device: {platform}. Allow it to join?` в `lib/presentation/app_root/` поверх любого экрана; строки EN + UK; тесты службы и виджета; голдены диалога — mobile + desktop

## Phase 4: User Story 2 — первое устройство с машины сервера (P1)

- [x] T010 [US2] Служебная страница `client_backend/internal/server/{status,status_page}.go`: состояния из `contracts/service-page-link.md` (ссылка сразу без устройств, `Add a device`, `Expires in 10 minutes`, `Link expired`, `New link`), `POST /link` (`Host`, `Origin`, токен формы); без печати ссылки в журнал (`announceClaim` уходит из `server.go`); тесты `status_test.go` (SC-004, SC-005)
- [x] T011 [US2] `noxd link`: `client_backend/internal/server/control.go` (`POST /control/link`: локальный `Host`, `X-Nox-Control: 1`, без `Origin`), подкоманда в `client_backend/main.go` (`-status-addr`); тесты (браузерный запрос с `Origin` — отказ, без заголовка — отказ)

## Phase 5: User Story 3 — все устройства потеряны (P1)

- [x] T012 [US3] Тест `client_backend/internal/server/pairing_test.go`: при спаренных устройствах ссылка с машины только по `Add a device`; новое устройство по ней — тот же человек и вся переписка; отзыв потерянного с нового рвёт его соединение (SC-003)

## Phase 6: User Story 4 — отзыв, выход, последнее устройство (P2)

- [x] T013 [US4] Выход с последнего устройства → «устройств нет», ссылка на странице сразу, человек и переписка на месте (`internal/store/devices.go`, `status.go`); приложение: выход — отзыв своего ключа, затем стирание (проверить `auth_repository_impl.dart`); тесты (SC-006)
- [x] T014 [US4] 2.1, 2.2, 7.8: экран входа без «только дома» и «не тот сервер» (`lib/presentation/pages/login_page/`, `qr_scan_page/`), 7.8 без onion-приглашений, подпись «только дома» — по `onion`/`public` (045); тесты; голдены изменённых состояний — mobile + desktop

## Phase 7: Polish & Cross-Cutting

- [x] T015 [P] Спецификация дизайна: `docs/design/spec/screens/pair-request.md` (новый: диалог), `connect.md` (ожидание), `{login,qr-scan,devices}.md`, `overview.md`; корпуса `docs/design/system/nox-{mobile,desktop}-screens/screens/`
- [x] T016 [P] Документы: `docs/client-backend/architecture/authentication.md` (кейсы без владельца и фразы, с подтверждением), `docs/blueprints/mobile/14-networking-and-auth.md`, `docs/client-backend/{README,demo-runbook}.md`, `scripts/demo-stand.sh` (без ссылки в журнале — `noxd link`), `client_backend/CLAUDE.md` (без владельца, инвариант 3 — новые события), `CLAUDE.md`
- [x] T017 Аудит журнала сервера: ни ссылки, ни токена (тест на вывод журнала при старте, выпуске и спаривании)
- [x] T018 Гейты: Go (`gofmt -l .`, `go vet ./...`, `go test -race ./...`), `make gate`, `make golden-verify`
- [x] T019 Сквозной прогон на macOS по `quickstart.md` §2; итог — в `research.md` (без интерфейса; проход по экранам обеих ширин и проверки на устройствах — за владельцем)
- [x] T020 Трекер `docs/client-backend/roadmap-security.md`: 046 реализована

## Dependencies & Execution Order

- T001 → T002 → T003 → T004 → T005 → (T006, T010, T011, T012, T013).
- Приложение: T007 после T005 → T008, T009; T014 — после T007.
- Polish — в конце; T018–T019 — последними.

## Implementation Strategy

MVP — US1 (приглашение с подтверждением) вместе с US2 (ссылка с машины): без ссылки с машины не спарить первое устройство. Затем US3, US4.
