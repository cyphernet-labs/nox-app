# Tasks: Tor отдельной службой — адреса сервера, `Use Tor` и раздел «Связь»

**Input**: Design documents from `specs/045-tor-service-addresses/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md; 044 влита в `security-rework`

**Tests**: обязательны: Go, Rust, Dart (юнит, блоки, виджеты), голдены обеих ширин для новых экранов и баннеров, сквозной прогон на macOS с отдельным tor.

**Organization**: контракт — первым; фундамент — сервер без tor, адреса в базе, модуль и приложение без ключей доступа, настройки связи; затем истории. Go — по скиллам `go-style`, `ws-rest-patterns`, `migrations`; каждый коммит с кодом — после своего гейта.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [ ] T001 Внести дельту в `docs/client-backend/protocol/contract-draft.md` по `contracts/wire-addresses.md`: §1 (onion — отдельная служба tor, один порт, сроки медленного пути для всех, без ключей доступа, PoW в настройках tor), §3 (`addresses.public`, `onion` из настроек сервера), `server.addresses`, §8A (без `access_key` и `device.setAccessKey`, claim через onion, порядок адресов ссылки, `onion`/`public` в ответе `device.invite`)
- [X] T002 [P] `packages/nox_tor/rust/Cargo.toml`: `arti-client` + `hs-pow-full`; убрать `ephemeral-keystore`, `tor-keymgr`, `tor-hscrypto` (`keymgr` остаётся выключателем хранилища ключей); `Cargo.lock`; `cargo check` всех целей, как в 044 (iOS, Android, macOS — настоящие; Linux, Windows — с заглушками C-инструментов)

---

## Phase 2: Foundational

### Сервер

- [ ] T003 Убрать tor из сервера: `client_backend/internal/tor/` целиком, `setupOnion`, onion-слушатель и сервер, `onionConnContext`/`markOnionConn`/`viaOnion`, интерфейс `torService` (`internal/server/{server,onion,ws,client}.go`), флаги `-tor`, `-tor-bin`, `-tor-dir` и `NOX_TOR*` (`internal/config/config.go`); сроки медленного пути для всех соединений (проверка канала 30 с, запись и pong 30 с, `ReadHeaderTimeout` 30 с); порядок остановки без onion и супервизора; тесты (`run_test`, `lifecycle_test`, `config_test`; удалить `onion_*_test.go`, `status_tor_test.go`)
- [ ] T004 Схема и хранилище адресов: `client_backend/migrations/001_init.sql` (`server_identity`: `public_address`, `onion_address`, `public_address_param`, `onion_address_param`; − `onion_seed`, − `devices.access_key` и индекс), `internal/store/serverkey.go` (чтение адресов, запись адреса, применение параметра в одной транзакции); тесты `internal/store/serverkey_test.go`
- [ ] T005 [P] Проверка адресов и параметры запуска в `client_backend/internal/server/address_settings.go`: onion v3 (base32, контрольная сумма `crypto/sha3`, версия), `host:port`; `-public-addr`/`NOX_PUBLIC_ADDR`, `-onion-addr`/`NOX_ONION_ADDR` в `internal/config/config.go`; применение при старте по правилу «появился или изменился», предупреждения; тесты `address_settings_test.go`
- [ ] T006 Снимок адресов в `client_backend/internal/server/addresses.go`: `Public` и `Onion` из базы, новая версия и рассылка `server.addresses` после записи; `addresses.public` в ответе `session.hello` (`handlers.go`); тесты `addresses_test.go`, `handlers` (SC-003)
- [ ] T007 Ключи доступа уходят: `device.setAccessKey` (`internal/server/pairing.go`, `ws.go`, `internal/protocol/frames.go`), `pair.access_key`, `internal/store/accesskeys.go`, `insertDevice` (`internal/store/identity.go`); тесты

### Rust-модуль

- [X] T008 `packages/nox_tor/rust/src/{lib,engine}.rs`: без `nox_tor_set_target`/`nox_tor_clear_target` и хранилища ключей; группа подстраховки — на каждый onion-сервис (`channel/target.rs`); `status.rs` — без классификации ошибок ключа доступа; тесты (`cargo test`, `clippy`, `fmt`)

### Приложение

- [ ] T009 Ключи доступа уходят из приложения: `lib/domain/repository/connection/access_key_repository.dart`, `lib/data/repository/connection/{access_key_repository_impl,connection_storage}.dart`, `lib/data/sync/connection/access_key_registrar.dart`, `lib/data/sync/{live_identity_handshake,live_session_starter}.dart`, `lib/data/remote/socket/nox_socket_client.dart` (`supportsAccessKeys`, `pair(accessKey)`), `lib/domain/model/connection/tor_status.dart`, `lib/data/repository/app/{session_repository_impl,auth_repository_impl}.dart`, `packages/nox_tor/lib/{nox_tor.dart,src/nox_tor_bindings.dart}` (`setTarget`/`clearTarget`), `lib/data/service/tor/{nox_tor_api,native_tor_service,fake_tor_service}.dart`; тесты из инвентаря (registrar, access key repo, selector, handshake, starter, socket client, session repo)
- [ ] T010 [P] Настройки связи: `lib/domain/model/connection/server_addresses.dart` (`public`, `manualAddress`, `manualOnion`, `useTor`; действующие адрес и onion; кандидаты), `lib/data/repository/connection/server_addresses_repository_impl.dart` (правила data-model: значение сервера сбрасывает правку того же поля), `lib/domain/repository/connection/server_addresses_repository.dart`, `lib/data/remote/socket/server_addresses_parser.dart` (`public`); тесты
- [ ] T011 [P] Tor на Linux: `lib/data/service/tor/tor_capability.dart`, `packages/nox_tor/lib/nox_tor.dart` (`isSupported` без `!Platform.isLinux`); тесты

**Checkpoint**: сервер без tor с адресами в базе; модуль и приложение без ключей доступа; гейты зелёные.

---

## Phase 3: User Story 1 — вне дома через Tor по галочке (P1) 🎯 MVP

- [ ] T012 [US1] `lib/data/sync/connection/connection_path_selector.dart`: Tor только при `useTor`, известном onion-адресе, поддержке платформы и неустаревшем клиенте; кандидаты напрямую — `lastGood`, ручной, публичный, найденные, из ссылки; ранний старт по `viaTorLast` — только с `useTor`; выключение `useTor` — остановка Tor и новый выбор пути; тесты `connection_path_selector_test.dart` (в том числе SC-006: при выключенной галочке Tor не запускается)
- [ ] T013 [US1] `test/data/sync/connection/lossless_switch_test.dart` и `test/live/tor_live_probe.dart`: переключение путей без ключей доступа, ровно один раз

---

## Phase 4: User Story 2 — владелец задаёт адреса на сервере (P1)

- [ ] T014 [US2] Служебная страница (`client_backend/internal/server/{status,status_page}.go`): найденные адреса, публичный и onion с `Set`, `POST /addresses` (`Host`, `Origin`, токен формы), `303` с `saved`/`invalid`, CSP `form-action 'self'`, предупреждения параметров; без вида tor; тесты `status_test.go` (подделка `Origin`, нет токена, чужой `Host`, испорченный onion — ничего не записано, удаление пустым значением)
- [ ] T015 [US2] Ссылки и приглашения (`client_backend/internal/server/{pairing_link,pairing,status}.go`, `server.go` `announceClaim`): порядок публичный → прямой → onion, onion и публичный — из базы; ответ `device.invite` с `onion` и `public`; claim через onion без отличия; тесты `pairing_link_test.go`, `pairing_test.go`
- [ ] T016 [P] [US2] `client_backend/cmd/smoke/main.go`: без `access_key`; ссылка с публичным и onion-адресом
- [ ] T017 [US2] Приглашение в приложении: `public` в ответе `device.invite` (`lib/data/remote/datasource/real/`, модель приглашения), подпись `This link works only on your home network.` — когда в ссылке нет ни onion, ни публичного адреса (`lib/presentation/pages/devices_page/bloc/devices_state.dart`); тесты `devices_bloc_test`

---

## Phase 5: User Story 3 — подключение по ссылке спаривания (P1)

- [ ] T018 [US3] Экран подключения `lib/presentation/pages/connect_page/` (`ConnectPage` с `route()`, `ConnectBloc` Freezed): поля «адрес сервера» и «onion-адрес» из ссылки, проверка формата, `Use Tor` (выключен) с подписью, `Connect`, причина под кнопкой, отказы токена и срока; вход: `login_page` (вставка + `Sign in`, картинка) и `qr_scan_page` ведут на него; `AuthRepository.signIn` (`lib/domain/repository/app/auth_repository.dart`, `lib/data/repository/app/auth_repository_impl.dart`) принимает настройки связи; строки EN + UK (`contracts/connection-ui.md`); тесты `connect_bloc_test`, виджетный; голдены `connect_page` mobile + desktop (пусто, с причиной, ошибка поля)
- [ ] T019 [US3] Спаривание через Tor (`live_identity_handshake.dart`, селектор): при `useTor` и onion-адресе — после неудачи напрямую, в том числе claim; тесты (SC-003 044: токен не уходит чужому ключу)

---

## Phase 6: User Story 4 — раздел «Связь» (P2)

- [ ] T020 [US4] `lib/presentation/pages/connection_page/` (`ConnectionBody`, `ConnectionPage` с `route()`, `ConnectionSettingsBloc`): поля, `Save` (изменено и годно), `Use Tor` сразу, строка причины; применённая правка → `SessionPhaseService.reconnect()`; строка `Connection` в `settings_root_page.dart` (обе ширины: `_Section.connection`, строка, пункт меню, заголовок, панель деталей); значки `assets/svg/icons/{lan,lan-fill}.svg` из `@material-symbols/svg-400` + `NoxIcons`, счётчики в `test/design/icons_resolution_test.dart`; тесты блока и виджета; голдены `connection_page` mobile + desktop, `settings_root_page` обеих ширин

---

## Phase 7: User Story 5 — понятное сообщение на каждую причину (P2)

- [ ] T021 [US5] `ConnectionProblem` (`lib/domain/model/connection/connection_problem.dart`): селектор пишет причину раунда (R12) → `PathSelection` → `ConnectionStatus.problem` (`connection_status_service_impl.dart`, `phase_connection_status_service.dart`) → состояния `chats_list`, `chat_thread`, `chat_card` → текст `AppNoticeStripWidget` вместо `No connection` (`otherServer` — вместо `serverNotRecognised`), `Try again` остаётся; строки EN + UK; тесты блоков; голдены баннеров (5.1, 5.2, 5.4 — обе ширины) для причины

---

## Phase 8: User Story 6 — сервер без встроенного tor (P2)

- [ ] T022 [US6] Тест `client_backend/internal/server/run_test.go`: `Run` не запускает внешних процессов и не знает флагов tor; onion-путь — через tor из `quickstart.md` (вручную); `-tor=false` больше не флаг (ошибка разбора с подсказкой)

---

## Phase 9: Polish & Cross-Cutting

- [ ] T023 [P] Спецификация дизайна: `docs/design/spec/screens/{connect,connection}.md` (новые), `{login,qr-scan,devices,chats-list,chat,chat-card}.md`, `docs/design/spec/overview.md` (отмена «путь выбирается сам», строки пути, состояния связи, приглашения); корпуса `docs/design/system/nox-mobile-screens/screens/` и `nox-desktop-screens/screens/` — новые экраны и изменённые
- [ ] T024 [P] Документы: блюпринты `docs/blueprints/mobile/{04-data-layer,05-presentation-layer,14-networking-and-auth}.md`, `docs/client-backend/{README,demo-runbook}.md`, `docs/client-backend/architecture/transport.md`, `scripts/demo-stand.sh` (tor отдельно, `-onion-addr`), `CLAUDE.md`, `client_backend/CLAUDE.md` (инварианты 1 и 9, файлы, флаги, тесты `TestOnion*`)
- [ ] T025 Логи: onion-адреса заменяются меткой и на сервере (замена из `internal/tor/logscrub.go` переезжает туда, где сервер пишет адреса) и в приложении; токены и ключи не пишутся; тесты
- [ ] T026 Гейты: `make tor-test`; в `client_backend/` — `gofmt -l .`, `go vet ./...`, `go test -race ./...`; `make gate`; `make golden-verify`
- [ ] T027 Сквозной прогон на macOS по `quickstart.md` §2 с tor из scratchpad; итог — в `research.md` («Проверка»)
- [ ] T028 Трекер `docs/client-backend/roadmap-security.md`: 045 реализована

---

## Dependencies & Execution Order

- T001 — первым. T002 параллельно.
- Сервер: T003 → T004 → T005, T006, T007 → T014, T015, T016, T022.
- Модуль: T008 после T002.
- Приложение: T009 (после T008 для привязок) → T010, T011 → T012 → T013; T017 после T015; T018–T021 после T010–T012.
- Polish — в конце; T026–T027 — последними.

## Parallel Example

```text
Go:   T003 → T004 → (T005 | T006 | T007) → (T014 | T015 | T016)
Rust: T002 → T008
Dart: T009 → (T010 | T011) → T012 → (T018 | T020 | T021), T017
```

## Implementation Strategy

MVP — US1 (Tor по галочке) вместе с US2 (адреса на сервере): без onion-адреса в базе Tor-пути нет. Затем US3 (экран подключения), US4, US5, US6.
