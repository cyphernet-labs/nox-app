# Tasks: Защищённый канал — TLS 1.3 и проверка Eidolon в Rust-модуле приложения

**Input**: Design documents from `specs/044-secure-channel/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: обязательны (решение владельца): юнит-тесты Rust, Go и Dart, виджетные и голдены изменённых экранов (mobile + desktop), сквозной прогон на macOS.

**Organization**: контракт — первым; фундамент — три линии (Rust-модуль, Go-сервер, Dart-канал), Dart зависит от C ABI модуля; затем истории пользователя, документы и гейты.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [ ] T001 Внести дельту канала в `docs/client-backend/protocol/contract-draft.md`: §1 (слои соединения, Eidolon, `/health` на служебном порту, без пиннинга), §2 (приветствие без `challenge`, векторы Eidolon вместо вектора challenge), §3 (`session.hello` без `device_key`/`signature`, незнакомый ключ → `unauthenticated`), §8A (`pair` без `device_key`; ссылка `nox://pair/` версии 3 вместо `https://nox.app/p/#`), коды ошибок — по `contracts/wire-channel.md` и `contracts/pairing-link-v3.md`
- [ ] T002 [P] Добавить в `packages/nox_tor/rust/Cargo.toml` зависимости `eidolon-auth =0.3.1`, `cyphergraphy =0.3.1` (`ed25519`), `ec25519 =0.1.0`, `tokio-rustls 0.26`; обновить `Cargo.lock`
- [ ] T003 [P] Положить общие векторы в тестовые данные трёх сторон: `client_backend/internal/eidolon/testdata/vectors.json`, `client_backend/internal/server/testdata/link-vectors.json`, `packages/nox_tor/rust/tests/data/eidolon-vectors.json`, `test/general/pairing/fixtures/link-vectors.json` (копии `contracts/*.json`)

---

## Phase 2: Foundational (блокирует все истории)

### Rust-модуль

- [ ] T004 [P] TLS канала в `packages/nox_tor/rust/src/channel/tls.rs`: `ClientConfig` только TLS 1.3 на `ring`, ALPN `http/1.1`, своя проверка (любой сертификат, подпись рукопожатия TLS 1.3 через `rustls::crypto::verify_tls13_signature`, TLS 1.2 — отказ), `with_no_client_auth`; функция экспортёра RFC 9266; юнит-тесты
- [ ] T005 [P] Eidolon-инициатор в `packages/nox_tor/rust/src/channel/eidolon.rs`: ключ из семени (`ec25519::KeyPair::from_seed`), `Cert`, `EidolonState::initiator` со списком из ожидаемого ключа сервера, запись 160 байт / чтение 160 байт, отображение ошибок (`Unauthorized` → `wrong_server`, остальные → `protocol`); тест по `tests/data/eidolon-vectors.json`
- [ ] T006 Цели соединения в `packages/nox_tor/rust/src/channel/target.rs`: прямой TCP; onion через `TorClient` движка с подстраховочным вторым подключением (логика переносится из `rust/src/bridge.rs`); виды ошибок Tor по `contracts/ffi-channel.md`
- [ ] T007 Реестр и насосы канала в `packages/nox_tor/rust/src/channel/{mod,registry}.rs`: открытие в рантайме движка, общий срок на транспорт + TLS + Eidolon, задача чтения с окном 1 МиБ и подтверждением, задача записи с очередью и событиями `WRITABLE`/`DRAINED`, `EOF`, `CLOSED` с видом отказа; семя — в обнуляемом буфере
- [ ] T008 C ABI в `packages/nox_tor/rust/src/lib.rs`: `nox_chan_open`, `nox_chan_write`, `nox_chan_ack`, `nox_chan_shutdown_write`, `nox_chan_close`, `nox_chan_buf_free` под `catch_unwind`; убрать `nox_tor_bridge_secret`; в `rust/src/engine.rs` `set_target` без моста (ключ доступа — в хранилище Arti); удалить петлевой мост из `rust/src/bridge.rs`
- [ ] T009 Интеграционные тесты канала в `packages/nox_tor/rust/tests/channel.rs`: локальный TLS 1.3-сервер на rustls с Eidolon-отвечающим — успех и обмен байтами в обе стороны, чужой ключ (`wrong_server`), посредник с двумя TLS-сессиями (`protocol`), сообщение не той длины, срок, `EOF`, окна (большой объём не раздувает очередь)

### Go-сервер

- [ ] T010 [P] Пакет `client_backend/internal/eidolon/eidolon.go`: сообщение (кодирование/разбор 160 байт), `Respond` (прочитать, проверить, ответить) и `Initiate` (для тестов и `cmd/smoke`) поверх `io.ReadWriter` со сроком, ошибки `InvalidLen`/`InvalidCert`/`SigMismatch`/`Unauthorized`; `eidolon_test.go` по `testdata/vectors.json` (побайтное совпадение обоих сообщений, ошибка посредника и чужого ключа)
- [ ] T011 [P] Ключ сервера Ed25519 в `client_backend/internal/store/serverkey.go` (семя и открытый ключ в `server_identity`, `ServerKey(ctx)`), `client_backend/migrations/001_init.sql` на месте; удалить ECDSA-ключ и `ErrLegacyServerKey`; тесты `internal/store/serverkey_test.go`
- [ ] T012 Технический сертификат в `client_backend/internal/server/tls.go`: одноразовый ключ ECDSA P-256 при каждом старте, TLS 1.3, `http/1.1`; удалить `PinnedTLSConfig`, `FingerprintOfSPKI`, `testdata/generate_pin_fixtures.go`; тест `tls_test.go`
- [ ] T013 Обёртка слушателя в `client_backend/internal/server/channel.go`: приём TCP, на каждое соединение — горутина с TLS-рукопожатием, экспортёром и `eidolon.Respond` под общим сроком, очередь готовых соединений для `Accept`, `ConnContext` с ключом устройства; закрытие слушателя рвёт идущие рукопожатия; тесты `channel_test.go` (успех, неверная подпись, посредник, медленный клиент не держит приём, срок)
- [ ] T014 Подключить обёртку в `client_backend/internal/server/server.go` для основного и onion-входа (`onion.go`), `/health` — на служебный слушатель (`status.go`); порядок остановки — прежний
- [ ] T015 Кадры в `client_backend/internal/protocol/frames.go`: приветствие без `challenge`, `session.hello` без `device_key`/`signature`, `pair` без `device_key`
- [ ] T016 Тестовая обвязка `client_backend/internal/server/server_test.go` и `integration_test.go`: клиент с `eidolon.Initiate` вместо пина и подписи challenge; перевести существующие тесты сервера на неё

### Dart-канал

- [ ] T017 Привязки и обёртка в `packages/nox_tor/lib/channel.dart` (+ `lib/src/nox_tor_bindings.dart`): `nox_chan_*`, `NativeCallable.listener`, `NoxChannelApi`/`NoxChannel` по `contracts/ffi-channel.md` (копирование и освобождение буферов, подтверждение входящих при доставке и не на паузе); убрать мост из `lib/nox_tor.dart`; тест `packages/nox_tor/test/channel_test.dart` (отказ по закрытому порту, неверные аргументы)
- [ ] T018 [P] `ChannelSocket` в `lib/data/remote/channel/channel_socket.dart`: `Stream<Uint8List> implements Socket` поверх `NoxChannel`; `addStream` с паузой источника по окну, `flush` до `DRAINED`, `close`/`destroy`, `done`; тест `test/data/remote/channel/channel_socket_test.dart` на фейковом канале
- [ ] T019 [P] `ChannelFailure` и `ChannelHttpClient` в `lib/data/remote/channel/{channel_failure,channel_http_client}.dart`: два `HttpClient` (сокет и передачи) с `connectionFactory` → `NoxChannelApi.open` (прямой адрес или onion с ключом доступа), `findProxy` `DIRECT`, привязка ключа сервера и семени устройства; тест `test/data/remote/channel/channel_http_client_test.dart`
- [ ] T020 Убрать `lib/data/remote/pinned_http_client.dart`, `lib/general/pairing/server_pin.dart` и их тесты (`server_pin_test`, `pinned_http_client_onion_test`, `transports_are_pinned_test`, `server_pin_callback_test`, фикстуры пина); перевести `lib/data/remote/socket/socket_channel_factory.dart` и `lib/data/remote/api_client.dart` на `ChannelHttpClient`; регистрация в `lib/di`

**Checkpoint**: модуль, сервер и Dart-канал собираются; тесты фундамента зелёные.

---

## Phase 3: User Story 1 — связь со своим сервером на любом пути (P1) 🎯 MVP

**Goal**: спаренное устройство обменивается сообщениями и файлами напрямую и через Tor по проверенному каналу.

**Independent Test**: сквозной прогон `quickstart.md` §2 шаги 1–3; тесты ниже.

- [ ] T021 [P] [US1] Приветствие без подписи в `lib/data/remote/socket/{nox_socket_client,server_frame}.dart` (`{srv:{schema_max}}`, `session.hello {schema, since?, label?}`); убрать `signChallenge` из `lib/general/pairing/device_keys.dart`; тесты `nox_socket_client_test.dart`
- [ ] T022 [P] [US1] Обработчик `session.hello` в `client_backend/internal/server/handlers.go`: ключ устройства из контекста соединения, незнакомый ключ → `unauthenticated`; тесты
- [ ] T023 [P] [US1] `/files` в `client_backend/internal/server/files.go`: ключ спаренного устройства на соединении и действующий токен (FR-006a), иначе 401; тесты `files_test.go`
- [ ] T024 [US1] `LiveSessionStarter` в `lib/data/sync/live_session_starter.dart`: привязка канала к ключу сервера и семени устройства вместо `pinTo`/`onionBridge`; эпоха `key:<ключ>`; `session.server_key` вместо отпечатка в `lib/data/repository/app/session_repository_impl.dart`; тесты
- [ ] T025 [US1] Путь через Tor без моста: `lib/data/service/tor/native_tor_service.dart`, `lib/domain/service/tor_service.dart` (без `TorBridgeEndpoint`), `lib/data/sync/connection/connection_path_selector.dart` (onion через модуль); тесты `native_tor_service_test`, `connection_path_selector_test`
- [ ] T026 [US1] Проба прямого адреса через канал в `lib/data/sync/connection/direct_prober.dart` (открыть канал с Eidolon и закрыть: «мой сервер» / «другой ключ» / «не ответил»); тест `direct_prober_test.dart`
- [ ] T027 [US1] Живая проверка `test/live/channel_probe.dart`: Dart-модуль против локально собранного `noxd` (спаривание по ссылке v3, `session.hello`, сообщение, загрузка и скачивание файла) — вручную, вне гейтов

**Checkpoint**: US1 проходит сквозной прогон на macOS.

---

## Phase 4: User Story 2 — чужая машина и посредник не проходят (P1)

**Goal**: чужой ключ и посредник отсекаются; «не тот сервер» не ведёт к выходу.

**Independent Test**: тесты ниже; `quickstart.md` §2 шаги 4–5.

- [ ] T028 [US2] Отказы канала в `lib/data/remote/socket/nox_socket_client.dart` и `lib/data/sync/connection/connection_path_selector.dart`: `wrongServer` по прямому адресу — адрес пропускается молча; по onion — `SessionPhase.serverMismatch`, попытки по нему стоп до смены адреса или `Try again`; `protocol`/`tls`/`network`/`timeout` — лестница повторов; тесты
- [ ] T029 [P] [US2] Тест посредника в `client_backend/internal/server/channel_test.go` (два TLS-соединения, пересылка сообщений проверки — сервер отказывает) и в `packages/nox_tor/rust/tests/channel.rs` (приложение отказывает)
- [ ] T030 [US2] Баннеры и состояния «не тот сервер» в `lib/presentation/pages/chats_list_page/`, `chat_thread_page/`, `chat_card_page/`: только путь через Tor; голдены mobile + desktop, где меняются

---

## Phase 5: User Story 3 — спаривание по ссылке версии 3 (P1)

**Goal**: ссылка `nox://pair/` версии 3 выпускается сервером и разбирается приложением; токен уходит только проверенному серверу.

**Independent Test**: векторы ссылки на обеих сторонах; спаривание по вставленной ссылке в сквозном прогоне.

- [ ] T031 [P] [US3] Ссылка v3 на сервере в `client_backend/internal/server/pairing_link.go` (ключ сервера, токен, прямой адрес и onion — TLV); тест `pairing_link_test.go` по `testdata/link-vectors.json`
- [ ] T032 [P] [US3] `pair` в `client_backend/internal/server/pairing.go` и `client_backend/internal/store/pairing.go`: ключ устройства из контекста соединения вместо поля `device_key`; тесты
- [ ] T033 [P] [US3] Разбор ссылки v3 в `lib/general/pairing/pairing_link.dart` (`PairingLink`, `LinkAddress`, отказы `malformed`/`newerVersion`; onion-адрес из ключа сервиса через модуль); тест `test/general/pairing/pairing_link_test.dart` по векторам
- [ ] T034 [US3] Вход по ссылке в `lib/data/repository/app/auth_repository_impl.dart` и `lib/data/sync/live_identity_handshake.dart`: сохранение ключа сервера и адресов, `pair` без `device_key`, без одноразовых ключей ссылки v2; тесты `auth_repository_impl_test`, `live_identity_handshake_test`
- [ ] T035 [US3] Экран входа и QR: `lib/presentation/pages/login_page/`, `qr_scan_page/` — отказы «испорченная ссылка» (`loginInvalidId`) и новая строка `loginLinkNewerVersion` (EN + UK в `lib/l10n/app_{en,uk}.arb`); тесты `login_bloc_test`; голдены `login_page` mobile + desktop для нового состояния
- [ ] T036 [P] [US3] `client_backend/cmd/smoke/main.go`: TLS без проверки сертификата + `eidolon.Initiate`, разбор ссылки v3

---

## Phase 6: User Story 4 — отозванное устройство уходит к спариванию (P2)

**Goal**: единственный путь к принудительному выходу — сервер не знает ключ устройства.

**Independent Test**: отозвать устройство и подключиться — стирание и экран спаривания; чужой сервер — без выхода.

- [ ] T037 [US4] Один хозяин принудительного выхода: `unauthenticated` на `session.hello` и `device.revoked` → выход; `lib/data/remote/interceptor/auth_interceptor.dart` — 401 больше не выход; тесты `auth_interceptor_test`, `app_root_logout_flow_test`
- [ ] T038 [US4] Старая сессия без `session.server_key` и нечитаемое семя устройства при запуске → стирание и экран спаривания (`lib/data/repository/app/session_repository_impl.dart`, `lib/data/repository/app/app_state_repository_impl.dart`); тесты

---

## Phase 7: User Story 5 — тот же канал на всех пяти платформах (P2)

**Goal**: модуль канала собирается на iOS, Android, macOS, Windows и Linux.

**Independent Test**: сборка macOS здесь; Windows и Linux — владелец.

- [ ] T039 [US5] Linux: `packages/nox_tor/hook/build.dart` больше не пропускает Linux, `packages/nox_tor/rust/rust-toolchain.toml` + Linux-цели, `NoxTor.isSupported` — модуль есть везде, `lib/data/service/tor/tor_capability.dart` — Tor на Linux выключен до 045; `packages/nox_tor/test/hook_test.dart`
- [ ] T040 [P] [US5] macOS: убрать `com.apple.security.network.server` из `macos/Runner/{DebugProfile,Release}.entitlements` (моста больше нет)

---

## Phase 8: Polish & Cross-Cutting

- [ ] T041 [P] Блюпринты `docs/blueprints/mobile/{01-stack-and-tooling,02-dependency-injection,04-data-layer,09-build-and-secrets-infra,14-networking-and-auth}.md` и `docs/blueprints/client-backend/README.md`: канал в модуле, без пиннинга и моста
- [ ] T042 [P] `CLAUDE.md` (разделы TLS с пиннингом, путь через Tor) и `client_backend/CLAUDE.md` (TLS, ключ сервера, ссылка): под канал 044
- [ ] T043 [P] Спецификация дизайна: `docs/design/spec/screens/{login,qr-scan}.md`, `docs/design/spec/overview.md`, корпуса `docs/design/system/nox-mobile-screens/screens/{2-1-login,2-2-qr-scan}.md` и `docs/design/system/nox-desktop-screens/screens/{04-login,06-qr}.md`: ссылка v3, отказы разбора, «не тот сервер» только по onion
- [ ] T044 [P] `docs/client-backend/demo-runbook.md`, `scripts/demo-stand.sh`: без отпечатка и `/health` на основном порту
- [ ] T045 Аудит логов: нет токенов, ссылок, ключей, подписей (Rust, Go, Dart)
- [ ] T046 Гейты: `make tor-test`; в `client_backend/` — `gofmt -l .`, `go vet ./...`, `go test -race ./...`; `make gate`; `make golden-verify`
- [ ] T047 Сквозной прогон на macOS по `quickstart.md` §2; итог — в `research.md` (раздел «Проверка»)
- [ ] T048 Трекер `docs/client-backend/roadmap-security.md`: 044 реализована

---

## Dependencies & Execution Order

- **Setup (T001–T003)**: T001 — первым (Принцип VII); T002–T003 параллельно.
- **Foundational (T004–T020)**: три линии параллельно — Rust (T004–T009), Go (T010–T016), Dart (T017–T020); T017 ждёт T008 (C ABI).
- **US1 (T021–T027)** после фундамента; **US2 (T028–T030)** и **US3 (T031–T036)** — после US1 (тот же код соединения); **US4 (T037–T038)** — после US1; **US5 (T039–T040)** — после фундамента, независимо.
- **Polish (T041–T048)** — в конце; T046–T047 — последними.

## Parallel Example

```text
# Фундамент тремя линиями:
Rust: T004, T005 → T006 → T007 → T008 → T009
Go:   T010, T011 → T012 → T013 → T014, T015 → T016
Dart: (после T008) T017 → T018, T019 → T020
```

## Implementation Strategy

MVP — US1: проверенный канал на любом пути. Затем US3 (ссылка v3 — без неё не спарить новое устройство), US2, US4, US5. Каждая история проверяется своими тестами; сквозной прогон — после US1 и в конце.
