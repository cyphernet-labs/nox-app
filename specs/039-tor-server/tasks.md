---
description: "Задачи фазы 039 — сервер в сети Tor"
---

# Tasks: Сервер в сети Tor — onion-адрес только для своих устройств

**Input**: документы из `specs/039-tor-server/` — [spec.md](./spec.md), [plan.md](./plan.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/wire-additions.md](./contracts/wire-additions.md), [quickstart.md](./quickstart.md)

**Tests**: обязательны. Это норма проекта (гейт Go `go test -race`, скилл `add-command`, п. 7) и требование спеки: каждый критерий успеха проверяется. Тесты через настоящий Tor включаются переменной `NOX_TOR_TEST_BIN` и без неё пропускаются.

**Organization**: задачи сгруппированы по историям спеки. Пути — от корня репозитория.

## Format: `[ID] [P?] [Story] Description`

- **[P]** — можно параллельно: другие файлы, нет зависимости от незавершённых задач.
- **[Story]** — история спеки: US1…US6.

---

## Phase 1: Setup (общая подготовка)

**Purpose**: контракт первым (Принцип VII), флаги и имена на проводе.

- [ ] T001 Внести добавления из `specs/039-tor-server/contracts/wire-additions.md` в `docs/client-backend/protocol/contract-draft.md`: §1 — onion как второй путь к тому же TLS-входу, claim через onion → `invalid_token` без траты токена; §3 — поле `addresses` в ответе `session.hello`; §8A — `access_key` в `pair`, команда `device.setAccessKey`, `onion` в `device.invite` и его ответе, событие `server.addresses`, ссылка версии `0x02` с таблицей раскладки. Без новых кодов ошибок, номер схемы прежний.
- [ ] T002 [P] Добавить флаги `-tor` (bool, по умолчанию `true`, env `NOX_TOR`), `-tor-bin` (env `NOX_TOR_BIN`), `-tor-dir` (по умолчанию `<db>-tor`, env `NOX_TOR_DIR`) в `client_backend/internal/config/config.go`, поля `Config.Tor`, `Config.TorBin`, `Config.TorDir`, с тестами разбора и значений по умолчанию в `client_backend/internal/config/config_test.go`.
- [ ] T003 [P] Добавить `CmdDeviceSetAccessKey = "device.setAccessKey"` и `EventServerAddresses = "server.addresses"` с doc-комментариями в `client_backend/internal/protocol/frames.go`.

---

## Phase 2: Foundational (блокирует все истории)

**Purpose**: схема, ключи, примитивы tor — на них стоят все истории.

**⚠️ CRITICAL**: истории не начинаются, пока фаза не закончена.

- [ ] T004 Добавить в `client_backend/migrations/001_init.sql` столбцы `server_identity.onion_key TEXT NOT NULL CHECK (onion_key <> '')`, `devices.access_key TEXT CHECK (access_key IS NULL OR access_key <> '')`, `pair_tokens.access_key TEXT CHECK (access_key IS NULL OR (kind = 'invite_device' AND access_key <> ''))` с комментариями в стиле файла (зачем, а не что). Правка на месте — правило до первого релиза (скилл `migrations`). Прогнать `go test ./internal/db/ ./internal/store/`, поправить фикстуры, которые вставляют строки `server_identity` вручную.
- [ ] T005 Создавать seed onion-ключа (32 байта, `crypto/rand`, base64) в той же транзакции, что TLS-ключ, в `EnsureServerIdentity`. Добавить узкий доступ `OnionSeed(ctx) ([]byte, error)` по образцу `ServerSigner` в `client_backend/internal/store/serverkey.go`. Тесты в `client_backend/internal/store/serverkey_test.go`: seed один и тот же между вызовами и переживает переоткрытие базы; в `ServerIdentity` закрытой части нет.
- [ ] T006 [P] Пакет `client_backend/internal/tor`, файл `onion.go`: `PublicKey(seed)`, `ExpandedKey(seed)` — формат `ED25519-V3`: clamp(SHA-512(seed)[0:32]) ‖ SHA-512(seed)[32:64]; `Address(pub)` — 56 знаков по rend-spec-v3, без `.onion`; `ClientAuthKey(pub)` — base32 без выравнивания для `ClientAuthV3`; `ParseAccessKey(b64)` — 32 байта x25519. Тесты в `client_backend/internal/tor/onion_test.go` по независимому вектору: seed из RFC 8032, тест 1 → открытый ключ из RFC → адрес, посчитанный отдельно Python-ом (`hashlib.sha3_256`).
- [ ] T007 [P] Файл `client_backend/internal/tor/binary.go`: `Find(flagPath)` — флаг, потом рядом с `os.Executable()` (`tor` или `tor.exe`), потом `exec.LookPath`; `ReadVersion(ctx, path)` по первой строке `tor --version`; `ParseVersion` и `AtLeast(0,4,9)`. Тесты разбора и сравнения версий в `client_backend/internal/tor/binary_test.go`, включая `0.4.8.x` — отказ, `0.4.9.13` и `0.5.0.1` — годятся, мусор — ошибка.
- [ ] T008 [P] Файл `client_backend/internal/tor/control.go`: клиент управляющего протокола. Одна горутина-читатель разводит `650` в канал событий, остальное — в канал ответов; многострочные `250+…` до `.`; `Command(ctx, line)` с тайм-аутом; `Authenticate(cookie)`. Тесты на фальшивом сервере через `net.Pipe` в `client_backend/internal/tor/control_test.go`: одно- и многострочные ответы, событие посреди ответа, ошибка `5xx`, тайм-аут, закрытие соединения.
- [ ] T009 [P] Файл `client_backend/internal/tor/logscrub.go`: заменить в строке журнала tor всё, что похоже на onion-адрес (56 знаков base32 и `.onion`, а также голые 56 знаков), на `[onion]`, и разобрать уровень строки (`[notice]`, `[warn]`, `[err]`). Тесты в `client_backend/internal/tor/logscrub_test.go`.
- [ ] T010 Файл `client_backend/internal/store/accesskeys.go`: `SetAccessKey(ctx, deviceKey, accessKey)` (заменяет; устройства нет → `ErrDeviceUnknown`), `ActiveAccessKeys(ctx, now) (keys []string, nextExpiry int64, err error)` — одна читающая транзакция по data-model, `CountDevicesWithAccess(ctx)`. Тесты в `client_backend/internal/store/accesskeys_test.go`: замена ключа, отзыв убирает ключ, использованное, истёкшее и погашенное приглашение выключает одноразовый ключ, `nextExpiry` — ближайший живой.

**Checkpoint**: схема, ключи и примитивы tor готовы.

---

## Phase 3: User Story 1 — Сервер достижим из любой сети (Priority: P1) 🎯 MVP

**Goal**: сервер публикует onion-адрес через свой tor; устройство с ключом доступа подключается из любой сети тем же TLS с тем же пином.

**Independent Test**: сквозной тест через настоящий Tor — клиент с зарегистрированным ключом подключается по onion, проходит пин и приветствие; адрес тот же после перезапуска.

- [ ] T011 [US1] Файл `client_backend/internal/tor/supervisor.go`. Тип `Supervisor`: `Run(ctx)` владеет процессом и управляющим соединением.
  - Запуск — каталог 0700, пустой torrc как `-f` и `--defaults-torrc`, параметры из research, решение 1. Ожидание `control.port`, `AUTHENTICATE` по cookie, `TAKEOWNERSHIP`, `SETEVENTS STATUS_CLIENT STATUS_GENERAL HS_DESC`, `GETINFO version`, `status/bootstrap-phase`, `status/version/current`.
  - Публикация: `ADD_ONION ED25519-V3:<раскрытый> Flags=V3Auth Port=443,<цель> ClientAuthV3=…`. «Опубликован» — по `HS_DESC UPLOADED` для своего адреса.
  - Снимок `Status` через `atomic.Pointer`, методы `Status()`, `KeysChanged()` (неблокирующий пинок, ёмкость 1), `Offered()`, `ReadyForInvite()`.
  - Управляющее соединение спрятано за интерфейсом, нужным для тестов (go-style: интерфейс там, где он потребляется).
  - Остановка: закрыть управляющее соединение, ждать выхода процесса до 10 с, затем `Kill`.
- [ ] T012 [US1] Тесты публикации на фальшивом управляющем соединении в `client_backend/internal/tor/supervisor_test.go`: при наличии ключей уходит `ADD_ONION` с `Flags=V3Auth`, портом 443 и каждым ключом; `HS_DESC UPLOADED` переводит в `published`; вердикт версии отображается по research, решение 8.
- [ ] T013 [US1] Внутренний onion-вход в `client_backend/internal/server/server.go`: слушатель `127.0.0.1:0` с тем же `tls.Config`, свой `http.Server` с `ReadHeaderTimeout` 30 с и `ConnContext`, который метит соединение как пришедшее через onion. Создание и запуск супервизора в `Run`, если `cfg.Tor`. Порядок остановки: оба HTTP-сервера → соединения → супервизор → хаб → база; инвариант 9 дополнен tor.
- [ ] T014 [US1] Метка onion на соединении в `client_backend/internal/server/ws.go` и `client_backend/internal/server/client.go`: поле `viaOnion` и тайм-ауты записи и ожидания pong 30 с для onion-соединений против 5 с для прямых. Тест в `client_backend/internal/server/server_test.go`: соединение через onion-вход помечено и получает свои тайм-ауты.
- [ ] T015 [US1] Ключ доступа на проводе в `client_backend/internal/server/pairing.go`: необязательный `access_key` в `pair` (проверка формы → `invalid_request`, запись в той же транзакции через `store.Pair`) и команда `device.setAccessKey` — только после приветствия, только для своего устройства. После ответа — `KeysChanged()`. Поддержка в `client_backend/internal/store/pairing.go` и `client_backend/internal/store/identity.go`: `insertDevice` пишет `access_key`, если он передан, и не стирает его, если нет. Маршрут — в `dispatch` в `client_backend/internal/server/ws.go`.
- [ ] T016 [US1] Тесты провода в `client_backend/internal/server/pairing_test.go`: `pair` с `access_key` сохраняет ключ; неверный `access_key` даёт `invalid_request`, и спаривания нет; `device.setAccessKey` до приветствия отклоняется; после приветствия заменяет ключ; пустой или неверный — `invalid_request`; повтор `pair` тем же токеном ключ не меняет.
- [ ] T017 [US1] Сквозной тест в `client_backend/internal/server/onion_test.go`, включается `NOX_TOR_TEST_BIN`, иначе `t.Skip`. Шаги:
  - сервер с Tor; спаривание claim с `access_key`;
  - второй tor-клиент с `ONION_CLIENT_AUTH_ADD`;
  - SOCKS5 → onion:443 → TLS с `PinnedTLSConfig` → WebSocket → `session.hello` с подписью;
  - перезапуск стека на той же базе — адрес тот же (SC-001, SC-003).

**Checkpoint**: сервер достижим через Tor для устройства с ключом.

---

## Phase 4: User Story 2 — Чужому onion-адрес ничего не даёт (Priority: P1)

**Goal**: без ключа соединения нет; пустой список — сервиса нет; отзыв и истечение ключа рвут доступ сразу; claim через onion невозможен.

**Independent Test**: клиент без ключа и отозванное устройство не подключаются; claim через onion — `invalid_token`, токен цел.

- [ ] T018 [US2] Пустой список в `client_backend/internal/tor/supervisor.go`: `ADD_ONION` не вызывается без единого ключа, а при опустевшем списке — `DEL_ONION`; статус `not-published-no-keys`. Тест в `client_backend/internal/tor/supervisor_test.go`: ни одной команды `ADD_ONION` без ключей.
- [ ] T019 [US2] Перепубликация в `client_backend/internal/tor/supervisor.go`. Объединение сигналов за 1 с; `DEL_ONION` + `ADD_ONION` с новым списком. Если хотя бы один ключ ушёл — через 5 с `GETINFO circuit-status` и `CLOSECIRCUIT` для `PURPOSE=HS_SERVICE_REND` с `REND_QUERY=<адрес>` (research, решение 15). Тесты на фальшивом соединении в `client_backend/internal/tor/supervisor_test.go`: пачка пинков даёт одну перепубликацию; при удалении ключа закрываются только сервисные цепочки своего адреса; при добавлении цепочки не трогаются.
- [ ] T020 [US2] Claim через onion в `client_backend/internal/store/pairing.go`: параметр `allowClaim` в `Pair`; для `TokenClaim` при `allowClaim == false` — `ErrTokenInvalid` до фиксации, транзакция откатывается, и токен остаётся неизрасходованным. Обработчик в `client_backend/internal/server/pairing.go` передаёт `!c.viaOnion`. Тесты в `client_backend/internal/store/pairing_test.go` и `client_backend/internal/server/pairing_test.go`: claim через onion-вход — `invalid_token`, после этого тот же токен по прямому пути проходит.
- [ ] T021 [US2] Отзыв в `client_backend/internal/server/pairing.go`: после ответа на `device.revoke` — `KeysChanged()`. Тест в `client_backend/internal/server/pairing_test.go`: отзыв даёт пинок супервизору, через фальшивый супервизор или наблюдаемый счётчик.
- [ ] T022 [US2] Сквозной тест в `client_backend/internal/server/onion_test.go`: клиент без ключа не подключается (SC-002); claim через onion — `invalid_token` (SC-005); после отзыва устройства и разрыва цепочек его ключ не открывает соединение (SC-004).

**Checkpoint**: onion закрыт для всех, кроме устройств с действующим ключом.

---

## Phase 5: User Story 3 — Без Tor сервер работает как раньше (Priority: P1)

**Goal**: любая неудача tor не задевает прямой путь; причина видна; tor не переживает сервер.

**Independent Test**: при выключенном, отсутствующем, слишком старом и упавшем tor прямой путь проходит все свои проверки.

- [ ] T023 [US3] Сбои в `client_backend/internal/tor/supervisor.go`:
  - tor не найден или старее 0.4.9 — фаза `binary-missing` или `binary-too-old`, перепроверка раз в 5 минут, `Offered() == false`;
  - процесс завершился — `waiting-retry` с паузой 1 с … 5 мин, сброс после жизни дольше минуты;
  - `Run` никогда не возвращает ошибку, кроме отмены контекста.

  Запуск процесса — за маленьким интерфейсом, нужным для тестов. Тесты в `client_backend/internal/tor/supervisor_test.go`: отсутствующий бинарь, старая версия, падение и перезапуск с ростом паузы.
- [ ] T024 [US3] Журнал tor в `client_backend/internal/tor/supervisor.go`: stdout процесса читается построчно и проходит `logscrub`; в журнал сервера идут `warn` и `err`, а `notice` — только о ходе подключения. Строка про `required protocol` даёт вердикт `obsolete` и последнюю ошибку.
- [ ] T025 [US3] Выключенный Tor в `client_backend/internal/server/server.go`: при `cfg.Tor == false` нет ни супервизора, ни onion-входа, ни onion-адреса. Тест в `client_backend/internal/server/server_test.go`: стек собирается и обслуживает приветствие без tor; `addresses.onion` отсутствует.

**Checkpoint**: без Tor — ровно прежнее поведение.

---

## Phase 6: User Story 4 — Устройство знает, где сервер (Priority: P2)

**Goal**: адреса в ответе на приветствие и событие `server.addresses` при их смене.

**Independent Test**: тестовый клиент получает `addresses` в приветствии и новое событие при смене снимка.

- [ ] T026 [US4] Новый файл `client_backend/internal/server/addresses.go`:
  - `directAddresses(bindAddr)` — обобщение `dialableHost`: все поднятые интерфейсы, IPv4 и IPv6, без loopback и link-local, порт основного входа, сортировка, не больше 16; при конкретной привязке — только она;
  - тип `addressSet` с `equal` и JSON-формой `{"direct":[…],"onion":"…"}`;
  - снимок `atomic.Pointer[addressSet]` на `Server`;
  - наблюдатель — горутина под errgroup: при старте, раз в 30 с и по пинку; рассылка события всем поприветствовавшим соединениям вне `s.mu` по образцу `announcePaired`.

  `dialableHost` переводится на общий код. Тесты в `client_backend/internal/server/addresses_test.go`: фильтры и предел 16 на подставных интерфейсах, равенство без учёта порядка, рассылка только поприветствовавшим.
- [ ] T027 [US4] Приветствие в `client_backend/internal/server/handlers.go`: поле `addresses` из снимка в `helloReply`; пометка «поприветствовал» под `s.mu` сразу после постановки ответа в очередь; после неё — сверка отправленного снимка с текущим и досылка события при расхождении. Тесты в `client_backend/internal/server/identity_test.go` или новом `client_backend/internal/server/addresses_test.go`: в ответе есть `addresses.direct`; событие приходит после ответа на приветствие и только поприветствовавшим.
- [ ] T028 [US4] Связь супервизора и наблюдателя в `client_backend/internal/server/server.go`: `addresses.onion` берётся из `Offered()` и адреса, вычисленного из seed при старте; изменение `Offered()` пинает наблюдателя (колбэк супервизора). Тест: появление первого ключа добавляет onion в снимок и рассылает событие — с фальшивым супервизором.

**Checkpoint**: устройства всегда знают текущие адреса сервера.

---

## Phase 7: User Story 5 — Второе устройство спаривается из другой сети (Priority: P2)

**Goal**: приглашение версии 2 с onion-адресом и одноразовым ключом; новое устройство спаривается через Tor и остаётся со своим ключом.

**Independent Test**: тестовый клиент спаривается по ссылке версии 2 через onion, подключается снова своим ключом; одноразовый ключ потом не работает.

- [ ] T029 [P] [US5] `BuildPairingLinkV2(addr, fingerprint, token, onionPub, onionPort, accessPriv)` по таблице контракта в `client_backend/internal/server/pairing_link.go`. Тесты в `client_backend/internal/server/pairing_link_test.go`: раскладка байт, длина 122 для IPv4, IPv6 и DNS-хост, неверные длины — ошибка.
- [ ] T030 [US5] `device.invite` с `onion: true` в `client_backend/internal/server/pairing.go`:
  - если `ReadyForInvite()` — пара x25519 из `crypto/ecdh`, `IssueDeviceInvite(ctx, userID, now, accessPub)`, ссылка версии 2, ответ `onion: true`, затем `KeysChanged()`;
  - иначе — ссылка версии 1 и `onion: false`;
  - без поля — как раньше, плюс `onion: false`;
  - при `viaOnion` прямой адрес берётся из снимка адресов, а не из `Host`.

  Поддержка в `client_backend/internal/store/pairing.go` (`IssueDeviceInvite` с `accessKey`). Тесты в `client_backend/internal/server/pairing_test.go`: все ветки, включая отсутствие закрытого ключа где-либо, кроме ссылки.
- [ ] T031 [US5] Истечение в `client_backend/internal/tor/supervisor.go`: таймер на `nextExpiry` из `ActiveAccessKeys` вызывает перепубликацию в момент истечения одноразового ключа — это удаление ключа, значит, с разрывом цепочек. Тест на фальшивом соединении с подставным временем.
- [ ] T032 [US5] Сквозной тест в `client_backend/internal/server/onion_test.go`: приглашение `onion: true` → разбор ссылки версии 2 → клиент с одноразовым ключом через onion делает `pair` со своим `access_key` → переподключение своим ключом и приветствие → одноразовый ключ не открывает соединение (SC-010).

**Checkpoint**: удалённое спаривание работает.

---

## Phase 8: User Story 6 — Видно, что с Tor (Priority: P2)

**Goal**: блок Tor на странице статуса в состоянии «забран».

**Independent Test**: страница показывает каждое состояние, и на ней нет ни onion-адреса, ни ключей.

- [ ] T033 [US6] Блок Tor в `client_backend/internal/server/status.go` и `client_backend/internal/server/status_page.go`:
  - включён ли Tor; версия; вердикт — рекомендована, устарела, не годится, неизвестно; подключение в процентах;
  - публикация — «опубликован», «публикуется», «не опубликован: нет устройств с доступом», «не опубликован: tor не работает»;
  - устройства с доступом «N из M»; последняя ошибка;
  - предупреждение при `outdated` и `obsolete`. Текст на английском.

  Тесты в `client_backend/internal/server/status_test.go`: каждое состояние через подставной снимок; ни одной строки, похожей на onion-адрес, ни в одном состоянии (SC-012).

**Checkpoint**: человек видит состояние Tor.

---

## Phase 9: Polish & Cross-Cutting

- [ ] T034 [P] `client_backend/CLAUDE.md`: шапка — «один статический бинарь без C-кода и процесс tor рядом»; инвариант 1 — tor как единственный соседний процесс, управляемый сервером и не открывающий базу; инвариант 9 — tor в порядке остановки; карта файлов — пакет `internal/tor`, `addresses.go`; эксплуатация — каталог `<db>-tor` и флаги; тесты — `NOX_TOR_TEST_BIN`. `client_backend/README.md`: запуск с tor и без него.
- [ ] T035 [P] Поправка конституции `.specify/memory/constitution.md` 1.3.0 → 1.3.1 (PATCH, уточнение формулировки): в рабочем режиме «одним статическим бинарником» → «одним статическим бинарником и процессом tor рядом, которым он управляет (фаза 039)». Обновить Sync Impact Report и строку версии и даты.
- [ ] T036 [P] Тест совместимости приложения в `test/data/remote/socket/nox_socket_client_test.dart`: ответ на приветствие с `addresses` проходит как обычно; событие `server.addresses` с `seq: 0` не меняет фазу и не ломает поток. При необходимости — то же для `SyncService` в `test/data/sync/` (SC-011).
- [ ] T037 [P] Обновить статус этапа 1 в `docs/client-backend/roadmap-tor.md` и одну строку о фазе 039 в `CLAUDE.md` в корне — раздел о фичах бэкенд-эры.
- [ ] T038 Гейты:
  - Go: `gofmt -l .` пусто → `go vet ./...` → `go test -race ./...`;
  - Dart (T036): `make gate` и `make golden-verify`;
  - сквозные: `NOX_TOR_TEST_BIN=<tor> go test -race -run TestOnion ./internal/server/`.
- [ ] T039 Ручная проверка по `specs/039-tor-server/quickstart.md`: сервер с tor и без, страница статуса, `kill -9` сервера и уход tor (SC-007), поиск onion-адреса в журнале (SC-012).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (T001–T003)** — сразу; T001 первым по Принципу VII.
- **Foundational (T004–T010)** — после Setup; T004 → T005 и T010 (схема нужна хранилищу); T006–T009 независимы.
- **US1 (T011–T017)** — после Foundational. Это MVP.
- **US2 (T018–T022)** — после T011 (супервизор) и T015 (ключи на проводе).
- **US3 (T023–T025)** — после T011, T013.
- **US4 (T026–T028)** — после T013; T028 — после T011.
- **US5 (T029–T032)** — после T015, T019; T029 независим.
- **US6 (T033)** — после T011, T010.
- **Polish (T034–T039)** — после историй; T038 и T039 последними.

### Within Each Story

Тесты пишутся рядом с кодом в одном шаге — так устроены задачи с `*_test.go`. Сквозные тесты через настоящий Tor идут последними в своей истории.

### Parallel Opportunities

- T002, T003 — параллельно с T001.
- T006, T007, T008, T009 — параллельно друг с другом: разные файлы пакета `internal/tor`.
- T029 — параллельно с остальным US5.
- T034, T035, T036, T037 — параллельно.

## Parallel Example: Foundational

```text
T006 internal/tor/onion.go      ┐
T007 internal/tor/binary.go     ├─ одновременно, разные файлы
T008 internal/tor/control.go    │
T009 internal/tor/logscrub.go   ┘
```

## Implementation Strategy

### MVP First

1. Setup + Foundational.
2. US1 — сервер достижим через Tor для устройства с ключом. Проверка — T017 через настоящий Tor.
3. **Stop and validate.**

### Incremental Delivery

US1 → US2 (закрыть доступ) → US3 (без Tor как раньше) → US4 (адреса) → US5 (удалённое спаривание) → US6 (страница) → Polish. Каждая история проверяется своими тестами и не ломает прежние; гейт Go — перед каждым коммитом.
