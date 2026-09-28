---
description: "Задачи фазы 039 — сервер в сети Tor"
---

# Tasks: Сервер в сети Tor — onion-адрес только для своих устройств

**Input**: документы из `specs/039-tor-server/` — [spec.md](./spec.md), [plan.md](./plan.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/wire-additions.md](./contracts/wire-additions.md), [quickstart.md](./quickstart.md)

**Tests**: обязательны — норма проекта (гейт Go `go test -race`, скилл `add-command`, п. 7) и требование спеки: каждый критерий успеха проверяется. Сквозные тесты через настоящий Tor называются `TestOnion*`, включаются переменной `NOX_TOR_TEST_BIN` и без неё пропускаются.

**Organization**: задачи сгруппированы по историям спеки. Пути — от корня репозитория. Редакция после `/speckit-analyze` (37 находок исправлены).

## Format: `[ID] [P?] [Story] Description`

- **[P]** — можно параллельно: другие файлы, нет зависимости от незавершённых задач.
- **[Story]** — история спеки: US1…US6.

---

## Phase 1: Setup — контракт и правила первыми

**Purpose**: Принцип VII — сначала контракт, потом код. Правила проекта называют tor раньше, чем он появится в коде, чтобы ни один промежуточный коммит не нарушал инвариант 1.

- [ ] T001 Внести добавления из `specs/039-tor-server/contracts/wire-additions.md` в `docs/client-backend/protocol/contract-draft.md`:
  - §1 — onion как второй путь к тому же TLS-входу, порт onion 443, claim через onion (в том числе повтор) → `invalid_token` без траты токена;
  - §2.1 — таблица кодов спаривания и правило эволюции: новая команда — только за признаком поддержки `addresses`;
  - §3 — поле `addresses` в ответе `session.hello` и его роль признака поддержки;
  - §8A — `access_key` в `pair`, команда `device.setAccessKey` с отказами `invalid_request` и `unauthenticated`, `onion` в `device.invite` (мягкий разбор) и `onion` в ответе, правило прямого адреса через onion, событие `server.addresses`, ссылка версии `0x02` с полями `onion_pub` и `one_time_priv` и длинами по типу хоста;
  - «внежурнальных событий» — четыре.

  У каждого добавления — отметка «сервер — фаза 039; приложение — этап 2 трека Tor». Новых кодов ошибок нет, номер схемы прежний.
- [ ] T002 Правила сервера в `client_backend/CLAUDE.md`:
  - шапка — «один статический бинарь без C-кода и процесс tor рядом»;
  - инвариант 1 — tor как единственный соседний процесс, управляемый сервером и не открывающий базу;
  - инвариант 3 — `server.addresses` в списке внежурнальных событий;
  - инвариант 7 — отметки соединения `greeted` и `addrVersion` под `s.mu` как инфраструктура реестра;
  - инвариант 9 — порядок остановки из research, решение 16;
  - карта файлов — `internal/tor/`, `internal/server/addresses.go`, `internal/store/accesskeys.go`;
  - эксплуатация — каталог `<db>-tor`, флаги `-tor`, `-tor-bin`, `-tor-dir`;
  - тесты — `NOX_TOR_TEST_BIN`.

  Запуск с tor и без него — в `client_backend/README.md`.
- [ ] T003 Поправка конституции `.specify/memory/constitution.md` 1.3.1 → 1.3.2 (PATCH): в рабочем режиме «одним статическим бинарником» → «одним статическим бинарником и процессом tor рядом, которым он управляет и который не открывает базу (фаза 039)». Переписать Sync Impact Report — он отстал на 1.2.0 → 1.3.0 — с записью одобрения владельца от 2026-10-03; обновить строку версии и даты. В корневом `CLAUDE.md` — «ratified at v1.3.0» → «v1.3.2», «Three off-journal events» → четыре, с `server.addresses`.
- [ ] T004 [P] Флаги в `client_backend/internal/config/config.go`:
  - `-tor` — bool, по умолчанию `true`, env `NOX_TOR`;
  - `-tor-bin` — env `NOX_TOR_BIN`;
  - `-tor-dir` — по умолчанию `<db>-tor`, env `NOX_TOR_DIR`;
  - поля `Config.Tor`, `Config.TorBin`, `Config.TorDir`.

  Тесты разбора и значений по умолчанию в `client_backend/internal/config/config_test.go`.
- [ ] T005 Только после T001: `CmdDeviceSetAccessKey = "device.setAccessKey"` и `EventServerAddresses = "server.addresses"` с doc-комментариями в `client_backend/internal/protocol/frames.go`; `server.addresses` — в тест внежурнальных имён `client_backend/internal/protocol/frames_test.go`.

---

## Phase 2: Foundational (блокирует все истории)

**⚠️ CRITICAL**: истории не начинаются, пока фаза не закончена.

- [ ] T006 Столбцы в `client_backend/migrations/001_init.sql` с комментариями в стиле файла:
  - `server_identity.onion_seed TEXT NOT NULL CHECK (onion_seed <> '')`;
  - `devices.access_key TEXT CHECK (access_key IS NULL OR access_key <> '')`;
  - `pair_tokens.access_key TEXT CHECK (access_key IS NULL OR (kind = 'invite_device' AND access_key <> ''))`.

  Правка на месте — правило до первого релиза. Ручной `INSERT INTO server_identity` в `client_backend/internal/store/serverkey_test.go:124` получает `onion_seed`.
- [ ] T007 В `client_backend/internal/store/serverkey.go`:
  - `EnsureServerIdentity` создаёт seed onion-ключа — 32 байта, base64 — в той же транзакции, что TLS-ключ;
  - узкий доступ `OnionSeed(ctx) ([]byte, error)`;
  - `ServerIdentity` onion-полей **не** получает.

  Тесты в `client_backend/internal/store/serverkey_test.go`: seed стабилен между вызовами и переоткрытием базы. Затем `go test ./internal/db/ ./internal/store/` — зелёные.
- [ ] T008 [P] `client_backend/internal/tor/onion.go`: `PublicKey(seed)`, `ExpandedKey(seed)` (`ED25519-V3`), `Address(pub)` (56 знаков, rend-spec-v3), `ClientAuthKey(pub)` (base32 без выравнивания), `ParseAccessKey(b64)` (32 байта). Тесты в `client_backend/internal/tor/onion_test.go` по независимому вектору:
  - seed RFC 8032, тест 1, `9d61b19d…7f60` → открытый `d75a9801…511a` → адрес `25njqamcweflpvkl73j4szahhihoc4xt3ktcgjnpaingr5yhkenl5sid`;
  - раскрытый ключ в base64 — `MHyDhk8oM8tCei7xwAoBPP3/J2jZgMCjpSDwBpBN6U+bTwr+KAt0aneGhOdUQlAgV7dHOgPwj5b1o46Sh+Afjw==`;
  - base32 байтов 0…31 — `AAAQEAYEAUDAOCAJBIFQYDIOB4IBCEQTCQKRMFYYDENBWHA5DYPQ`.

  Все три посчитаны Python независимо от кода.
- [ ] T009 [P] `client_backend/internal/tor/binary.go`: `Find(flagPath)` — явный путь **окончателен**, без провала дальше; иначе рядом с `os.Executable()` (`tor`, `tor.exe`), иначе `exec.LookPath`. Плюс `ReadVersion`, `ParseVersion`, `AtLeast(0,4,9)`. Тесты в `client_backend/internal/tor/binary_test.go`: явный несуществующий путь даёт «не найден», даже если tor есть в `PATH`; `0.4.8.x` — отказ; `0.4.9.13` и `0.5.0.1` — годятся; мусор — ошибка.
- [ ] T010 [P] `client_backend/internal/tor/control.go`: клиент управляющего протокола. Одна горутина-читатель разводит `650` в канал событий, остальное — в канал ответов; многострочные `250+…` до `.`; `Command(ctx, line)` с тайм-аутом; `Authenticate(cookie)`. **Ошибка называет только глагол команды** — без аргументов и строк ответа. Тесты в `client_backend/internal/tor/control_test.go` через `net.Pipe`: одно- и многострочные ответы, событие посреди ответа, `5xx`, тайм-аут, закрытие; ошибка `ADD_ONION … ClientAuthV3=СЕКРЕТ` не содержит `СЕКРЕТ`.
- [ ] T011 [P] `client_backend/internal/tor/logscrub.go`: в строке заменить onion-адреса (56 знаков base32 с `.onion` и без) на `[onion]`, цепочки base64 и base32 от 40 знаков на `[key]`; разобрать уровень строки (`[notice]`, `[warn]`, `[err]`). Тесты в `client_backend/internal/tor/logscrub_test.go`.
- [ ] T012 `client_backend/internal/store/accesskeys.go`:
  - `SetAccessKey(ctx, deviceKey, accessKey)` — заменяет ключ; нет устройства → `ErrDeviceUnknown`;
  - `ActiveAccessKeys(ctx, now) (keys []string, nextExpiry int64, err error)` — одна читающая транзакция, без повторов;
  - `CountDevicesWithAccess(ctx)`.

  Тесты в `client_backend/internal/store/accesskeys_test.go`: замена; отзыв убирает ключ; использованное, истёкшее и погашенное приглашение выключает одноразовый ключ; повторы схлопываются; `nextExpiry` — ближайший живой.
- [ ] T013 Тестовая обвязка в `client_backend/internal/server/server_test.go`:
  - `openStack` синхронно считает первый снимок адресов;
  - по желанию поднимает второй TLS-вход, помеченный как onion, — тот же `ConnContext`, что в `Run`;
  - принимает подставную реализацию Tor: счётчик `KeysChanged`, управляемые `ReadyForInvite`, `Offered`, `Status`, `OnionPublicKey`;
  - помощник подключения к onion-входу.

**Checkpoint**: схема, ключи, примитивы tor и обвязка готовы.

---

## Phase 3: User Story 1 — Сервер достижим из любой сети (Priority: P1) 🎯 MVP

**Goal**: сервер публикует onion-адрес через свой tor — и **никогда** без ключей; устройство с ключом подключается из любой сети тем же TLS с тем же пином.

**Independent Test**: `TestOnionReach` через настоящий Tor.

- [ ] T014 [US1] Супервизор в `client_backend/internal/tor/supervisor.go`:
  - **Запуск:** каталог 0700, пустой torrc как `-f` и `--defaults-torrc`, параметры из research, решение 1 — `--SocksPort 0`, `--ClientOnly 1`, без `NonAnonymous`. Ожидание `control.port`, `AUTHENTICATE`, `TAKEOWNERSHIP`, `SETEVENTS STATUS_CLIENT STATUS_GENERAL HS_DESC`, `GETINFO version`, `status/bootstrap-phase`, `status/version/current`.
  - **Публикация** — **только при ключах ≥ 1**: `ADD_ONION ED25519-V3:<раскрытый> Flags=V3Auth Port=443,<цель> ClientAuthV3=…`. «Опубликован» — по `HS_DESC UPLOADED` своего адреса.
  - **Вердикт:** таблица из research, решение 8; перечитывается при `STATUS_GENERAL` и раз в 10 минут. Предупреждения подключения из `STATUS_CLIENT` (`WARNING`, `REASON`, `CLOCK_SKEW`) идут в последнюю ошибку через `logscrub`.
  - **Снимок** `Status` через `atomic.Pointer`. Методы: `Status()`, `KeysChanged()` (неблокирующий пинок, ёмкость 1), `Offered()`, `ReadyForInvite()` (предикаты — data-model), `OnionPublicKey()`, `Address()`. seed пакет не покидает.
  - **Интерфейсы** — управляющее соединение и запуск процесса. Плюс выключенная реализация `Disabled()` с теми же методами (research, решение 17).
  - **Остановка:** закрыть управляющее соединение, ждать выхода до 10 с, затем `Kill`.
- [ ] T015 [US1] Тесты в `client_backend/internal/tor/supervisor_test.go` на подставных соединении и запуске:
  - при нуле ключей **ни одного** `ADD_ONION`;
  - при ключах — `ADD_ONION` с `Flags=V3Auth`, портом 443 и каждым ключом;
  - аргументы запуска содержат `--SocksPort 0` и `--ClientOnly 1` и не содержат `NonAnonymous`;
  - `HS_DESC UPLOADED` → `published`; отображение вердиктов; предупреждение `STATUS_CLIENT` → последняя ошибка;
  - упавший `ADD_ONION` не оставляет ни ключа, ни адреса ни в журнале, ни в `Status()`.
- [ ] T016 [US1] Сборка в `client_backend/internal/server/server.go`, в `Run`:
  - **onion-вход:** `127.0.0.1:0`, тот же `tls.Config`, `TLSNextProto` — пустая карта, как у основного; `ReadHeaderTimeout` 30 с; `ConnContext` метит соединения;
  - **супервизор** при `cfg.Tor`, со **своим** контекстом;
  - **первый снимок адресов** — синхронно до слушателей;
  - **порядок остановки** из research, решение 16: три сервера → параллельное закрытие WebSocket-соединений в `CloseConnections` → `WaitConnections` до 15 с → наблюдатель и супервизор → хаб → база.
- [ ] T017 [US1] Метки и тайм-ауты соединения в `client_backend/internal/server/client.go` и `client_backend/internal/server/ws.go`:
  - `viaOnion`;
  - поля тайм-аутов записи и ожидания pong — 30 с для onion, 5 с для прямых;
  - ошибка `websocket.Accept` на onion-входе пишется без текста библиотеки.

  Тесты в `client_backend/internal/server/server_test.go`:
  - соединение через onion-вход помечено;
  - масштабированная проверка SC-009: клиент, отвечающий на ping с задержкой меньше onion-тайм-аута, но больше прямого, держится на onion и рвётся на прямом;
  - `GET /` на onion-входе даёт 404 — страницы статуса там нет.
- [ ] T018 [US1] Ключ доступа на проводе.
  - `pair` в `client_backend/internal/server/pairing.go` принимает необязательный `access_key`: неверная форма → `invalid_request`, и спаривания нет.
  - `store.Pair` в `client_backend/internal/store/pairing.go` получает структуру параметров `PairOptions{AccessKey string; ViaOnion bool}` вместо голого булева. Места вызова: `internal/server/pairing.go:85`, `internal/server/chats_test.go:332`, `internal/server/server_test.go:200`, `internal/store/stats_test.go:35`, помощник `internal/store/pairing_test.go:18`.
  - `insertDevice` в `client_backend/internal/store/identity.go` пишет ключ, если он передан, и не стирает, если нет.
  - Команда `device.setAccessKey`: только после приветствия, только для своего устройства; `ErrDeviceUnknown` → `unauthenticated`; тот же ключ — без пинка.
  - После ответа — `KeysChanged()`. Маршрут — в `dispatch`.
- [ ] T019 [US1] Тесты в `client_backend/internal/server/pairing_test.go`:
  - `pair` с `access_key` сохраняет ключ; неверный — `invalid_request`, спаривания нет;
  - повтор `pair` ключ не меняет;
  - `device.setAccessKey` до приветствия отклоняется, после — заменяет; пустой или неверный — `invalid_request`;
  - отозванное посреди сессии устройство — `unauthenticated`;
  - при `cfg.Tor = false` ключ принимается и сохраняется;
  - пинок уходит после ответа.
- [ ] T020 [US1] `TestOnionReach` в `client_backend/internal/server/onion_test.go` (`NOX_TOR_TEST_BIN`, иначе `t.Skip`):
  - сервер с Tor; claim с `access_key`; tor-клиент с `ONION_CLIENT_AUTH_ADD`;
  - SOCKS5 → onion:443 → TLS с `PinnedTLSConfig` → WebSocket → подписанный `session.hello`;
  - `message.send`, затем `file.uploadBegin` с PUT и `file.downloadBegin` с GET по HTTPS через тот же SOCKS — штатный SOCKS5-прокси `net/http`, без новых зависимостей (SC-001);
  - журнал сервера без onion-адреса и ключей (SC-012);
  - перезапуск на той же базе и `VACUUM INTO` в новый файл дают тот же адрес (SC-003).

**Checkpoint**: сервер достижим через Tor для устройства с ключом; без ключей сервиса нет.

---

## Phase 4: User Story 2 — Чужому onion-адрес ничего не даёт (Priority: P1)

- [ ] T021 [US2] Опустевший список в `client_backend/internal/tor/supervisor.go`: `DEL_ONION` и через 5 с разрыв сервисных цепочек, статус `not-published-no-keys`. Тест в `client_backend/internal/tor/supervisor_test.go`.
- [ ] T022 [US2] Перепубликация в `client_backend/internal/tor/supervisor.go`:
  - пинки за 1 с объединяются;
  - неизменившееся множество ключей — без перепубликации;
  - иначе `DEL_ONION` + `ADD_ONION`; если хотя бы одного прежнего ключа нет — разность множеств, — через 5 с `GETINFO circuit-status` и `CLOSECIRCUIT` для `PURPOSE=HS_SERVICE_REND` с `REND_QUERY=<адрес>`.

  Тесты: пачка пинков — одна перепубликация; обмен «одноразовый на постоянный» рвёт цепочки; только добавление — не рвёт; чужие цепочки и цепочки других назначений не трогаются.
- [ ] T023 [US2] Claim через onion в `client_backend/internal/store/pairing.go`:
  - при `opts.ViaOnion` и токене `claim` — `ErrTokenInvalid` до фиксации, и токен цел;
  - то же для **повтора** израсходованного claim — `pairedBy` возвращает и тип токена.

  Обработчик передаёт `ViaOnion: c.viaOnion`. Тесты в `client_backend/internal/store/pairing_test.go` и `client_backend/internal/server/pairing_test.go`: claim через onion-вход — `invalid_token`, после него тот же токен по прямому пути проходит; повтор claim через onion — `invalid_token`.
- [ ] T024 [US2] Отзыв в `client_backend/internal/server/pairing.go`: после ответа на `device.revoke` — `KeysChanged()`. Тест на подставной реализации Tor в `client_backend/internal/server/pairing_test.go`.
- [ ] T025 [US2] `TestOnionAccess` в `client_backend/internal/server/onion_test.go`:
  - 20 попыток клиента без ключа — ни одного соединения (SC-002);
  - claim через onion → `invalid_token` (SC-005);
  - после отзыва устройства его ключ не открывает соединение в течение минуты (SC-004).

---

## Phase 5: User Story 3 — Без Tor сервер работает как раньше (Priority: P1)

- [ ] T026 [US3] Сбои в `client_backend/internal/tor/supervisor.go`:
  - tor не найден или старее 0.4.9 → `binary-missing` или `binary-too-old`, перепроверка раз в 5 минут, `Offered() == false`;
  - процесс завершился → `waiting-retry` с паузой 1 с … 5 мин, сброс после жизни дольше минуты;
  - `Run` возвращает только при отмене контекста.

  Тесты на подставном запуске в `client_backend/internal/tor/supervisor_test.go`.
- [ ] T027 [US3] Журнал tor в `client_backend/internal/tor/supervisor.go`: stdout процесса построчно через `logscrub`; в журнал сервера — `warn`, `err` и `notice` о ходе подключения; строка про `required protocol` → вердикт `obsolete` и последняя ошибка. Тест на подставном выводе.
- [ ] T028 [US3] Выключенный Tor в `client_backend/internal/server/server.go`: при `cfg.Tor == false` — `tor.Disabled()`, без onion-входа и onion-адреса. Тест в `client_backend/internal/server/server_test.go` вызывает **`Run` напрямую** на свободном порту и временной базе с `-tor=false`: `/health` отвечает, в приветствии нет `addresses.onion`, остановка по отмене контекста чистая.

---

## Phase 6: User Story 4 — Устройство знает, где сервер (Priority: P2)

- [ ] T029 [US4] `client_backend/internal/server/addresses.go`:
  - `directAddresses(bindAddr)` — обобщение `dialableHost`: поднятые интерфейсы, IPv4 и IPv6, без loopback и link-local, сортировка, не больше 16; конкретная привязка — она, если это не loopback;
  - `addressSet{version, direct, onion}` с `equal` и JSON;
  - поля `client.greeted` и `client.addrVersion` под `s.mu`;
  - наблюдатель — **единственный отправитель** события: кладёт снимок, потом собирает получателей с `addrVersion < version` и отправляет вне `s.mu`; запускается при старте, раз в 30 с и по пинку.

  `dialableHost` переходит на общий код. Тесты в `client_backend/internal/server/addresses_test.go`: фильтры и предел на подставных интерфейсах; loopback-привязка — пусто; равенство без учёта порядка; рассылка только поприветствовавшим.
- [ ] T030 [US4] Приветствие в `client_backend/internal/server/handlers.go`: `addresses` из снимка; после постановки ответа в очередь — под `s.mu` `greeted = true` и `addrVersion = version` отправленного снимка; затем пинок наблюдателю. Тесты в `client_backend/internal/server/addresses_test.go`:
  - `addresses.direct` есть всегда;
  - событие не приходит раньше ответа;
  - смена снимка между чтением и отметкой даёт событие с новым снимком;
  - старый список после нового не приходит.
- [ ] T031 [US4] Связь в `client_backend/internal/server/server.go`: `addresses.onion` = `Address()` + `:443`, пока `Offered()`; смена `Offered()` пинает наблюдателя (колбэк супервизора). Тест на подставной реализации: первый ключ добавляет onion и рассылает событие не позже чем за минуту (SC-008).

---

## Phase 7: User Story 5 — Второе устройство спаривается из другой сети (Priority: P2)

- [ ] T032 [P] [US5] `BuildPairingLinkV2(addr, fingerprint, token, onionPub, onionPort, oneTimePriv)` в `client_backend/internal/server/pairing_link.go`. Тесты в `client_backend/internal/server/pairing_link_test.go`: раскладка; длина 122 для IPv4, 134 для IPv6, 119 + N для DNS; неверные длины — ошибка; claim-ссылка при включённом Tor остаётся версии 1.
- [ ] T033 [US5] `device.invite` в `client_backend/internal/server/pairing.go`:
  - мягкий разбор `onion`: нет, `null` или не-bool — как `false`;
  - `onion: true` и `ReadyForInvite()` → пара x25519 через `crypto/ecdh`; новый метод `store.IssueOnionInvite(ctx, userID, accessPub, now)`, а `IssueDeviceInvite` не трогается; ссылка версии 2 с `OnionPublicKey()`; ответ `onion: true`; `KeysChanged()`;
  - иначе — версия 1 и `onion: false`;
  - при `viaOnion` прямой адрес — первый IPv4 из снимка, иначе первый адрес, иначе адрес привязки.

  Тесты в `client_backend/internal/server/pairing_test.go`: все ветки; закрытого одноразового ключа нет ни в базе, ни в журнале — только в ссылке.
- [ ] T034 [US5] Истечение в `client_backend/internal/tor/supervisor.go`: таймер на `nextExpiry` перепубликует сервис в момент истечения одноразового ключа — это удаление ключа, значит, с разрывом цепочек. Тест с подставным временем.
- [ ] T035 [US5] `TestOnionInvite` в `client_backend/internal/server/onion_test.go`:
  - приглашение `onion: true` → разбор ссылки версии 2;
  - клиент с одноразовым ключом через onion делает `pair` со своим `access_key`;
  - переподключение своим ключом и приветствие;
  - одноразовый ключ больше не открывает соединение (SC-010).

---

## Phase 8: User Story 6 — Видно, что с Tor (Priority: P2)

- [ ] T036 [US6] Блок Tor в `client_backend/internal/server/status.go` и `client_backend/internal/server/status_page.go`:
  - в состоянии «забран» — полный блок по FR-027: фаза, версия, вердикт, публикация, устройства «N из M», последняя ошибка;
  - в состоянии «не забран» — одна строка о Tor;
  - строки — из таблицы data-model, на английском; предупреждение при `outdated` и `obsolete`; «Tor disabled» при выключенном.

  Тесты в `client_backend/internal/server/status_test.go`: каждое состояние через подставной снимок; ни в одном нет строки, похожей на onion-адрес или ключ (SC-012).

---

## Phase 9: Polish & Cross-Cutting

- [ ] T037 [P] Совместимость приложения в `test/data/remote/socket/nox_socket_client_test.dart`: ответ на приветствие с `addresses` проходит как обычно; событие `server.addresses` с `seq: 0` не меняет фазу и не ломает поток. При необходимости — то же для `SyncService` в `test/data/sync/` (SC-011). Коммит — только после `make gate` и `make golden-verify`.
- [ ] T038 [P] Статус этапа 1 в `docs/client-backend/roadmap-tor.md`.
- [ ] T039 Гейты:
  - Go: `gofmt -l .` пусто → `go vet ./...` → `go test -race ./...`;
  - **в `go.mod` по-прежнему ровно четыре прямых `require`** (FR-033, SC-013);
  - сквозные: `NOX_TOR_TEST_BIN=<tor> go test -race -run 'TestOnion' -timeout 15m ./internal/server/`;
  - Dart (T037): `make gate` и `make golden-verify`.
- [ ] T040 Ручная проверка по `specs/039-tor-server/quickstart.md`: сервер с tor и без, страница статуса в обоих состояниях, `kill -9` сервера и уход tor (SC-007), поиск onion-адреса и ключей в журнале (SC-012).

---

## Dependencies & Execution Order

- **Phase 1**: T001 первым; T005 — строго после T001; T002 и T003 — до любого кода с tor; T004 — параллельно.
- **Phase 2**: T006 → T007 → T012; T008–T011 независимы; T013 — после T007.
- **US1 (T014–T020)** — после Phase 2. Это MVP; запрет публикации без ключей входит в него.
- **US2 (T021–T025)** — после T014 и T018.
- **US3 (T026–T028)** — после T014 и T016.
- **US4 (T029–T031)** — после T016; T030 — после T029; T031 — после T014 и T029.
- **US5 (T032–T035)** — T033 после T014 (`ReadyForInvite`, `OnionPublicKey`), T018 и T029 (снимок); T034 после T022; T032 независим.
- **US6 (T036)** — после T014 и T012.
- **Polish** — после историй; T039 и T040 последними.

## Parallel Example: Foundational

```text
T008 internal/tor/onion.go      ┐
T009 internal/tor/binary.go     ├─ одновременно, разные файлы
T010 internal/tor/control.go    │
T011 internal/tor/logscrub.go   ┘
```

## Implementation Strategy

MVP — Phase 1, Phase 2 и US1, проверка — `TestOnionReach`. Дальше: US2 → US3 → US4 → US5 → US6 → Polish. Гейт Go — перед каждым коммитом; гейт Dart — перед коммитом T037.
