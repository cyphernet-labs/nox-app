# Implementation Plan: Защищённый канал — TLS 1.3 и проверка Eidolon в Rust-модуле приложения

**Branch**: `044-secure-channel` (от `security-rework`, PR — в `security-rework`) | **Date**: 2026-10-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/044-secure-channel/spec.md`

## Summary

Каждое соединение приложения с сервером — и `wss` для команд, и `https` для байтов файлов — собирается в Rust-модуле приложения: TCP или поток Arti → TLS 1.3 (rustls на ring, сертификат не сверяется, подпись рукопожатия проверяется) → проверка Eidolon (`eidolon-auth`: приложение показывает ключ устройства первым, сервер отвечает, приложение сверяет ключ сервера с ключом из ссылки) → поток байтов в Dart через FFI. В Dart свой `Socket` поверх модуля отдаётся `HttpClient` через `connectionFactory` — WebSocket и Dio не меняются. `PinnedHttpClient`, `ServerPin`, петлевой мост Tor и подпись challenge в приветствии уходят.

Сервер принимает TCP сам, на каждое соединение — TLS 1.3 с техническим сертификатом и Eidolon (своя реализация по правилам `eidolon-auth`, сверенная общими векторами), и только потом отдаёт соединение `http.Server`; ключ устройства — в контексте запроса. Ключ сервера становится Ed25519. Ссылка спаривания — `nox://pair/` версии 3 с TLV-адресами. `/health` уходит со служебного порта.

Интерфейс почти не меняется: новые отказы разбора ссылки и сообщение «onion-адрес ведёт к другому серверу».

## Technical Context

**Language/Version**: Dart 3.12 (Flutter `3.44.1`, FVM) — приложение; Rust 1.93.1 — модуль `packages/nox_tor`; Go `1.27` — сервер.

**Primary Dependencies**:
- Rust: `rustls` 0.23.45 (`ring`), `tokio-rustls` 0.26.6, `eidolon-auth` 0.3.1, `cyphergraphy` 0.3.1 (`ed25519`), `ec25519` 0.1.0, `arti-client` 0.47.0 (как сегодня), `zeroize`.
- Dart: `dart:ffi` (`NativeCallable.listener`), `dart:io` (`Socket`, `HttpClient.connectionFactory`), `web_socket_channel`, Dio — как сегодня; `cryptography` — только для семени и открытого ключа устройства.
- Go: stdlib (`crypto/tls`, `crypto/ed25519`, `crypto/ecdsa`, `crypto/x509`, `net`, `net/http`), `coder/websocket`, `modernc.org/sqlite` — новых зависимостей нет.

**Storage**: сервер — `server_identity` хранит семя и открытый ключ Ed25519 (`001_init.sql` на месте); приложение — `session.server_key` вместо `session.server_fingerprint`, эпоха `key:`. Миграций нет.

**Testing**: Rust — `cargo test` (векторы, канал против локального TLS-сервера с Eidolon); Go — `go test -race ./...` (векторы, слушатель, посредник, `/files`); Dart — `flutter_test`, `bloc_test`, `mockito` (векторы ссылки, `ChannelSocket` поверх фейка, сессия, приветствие, спаривание, проба), голдены обеих ширин для изменённых экранов входа; сквозной прогон на macOS (`quickstart.md`).

**Target Platform**: приложение — iOS, Android, macOS, Windows, Linux (модуль канала — везде; Tor в интерфейсе Linux — с 045); сервер — Linux, macOS, Windows.

**Project Type**: мобильное + десктопное приложение, нативный модуль, Go-сервер; меняется контракт v0 (§1, §2, §3, §8A).

**Performance Goals**: соединение с проверкой дома — меньше секунды (SC-006); проверка — один обмен двумя сообщениями по 160 байт.

**Constraints**: без локальных портов; паника не пересекает FFI; окна 1 МиБ в обе стороны; логи без токенов, ссылок, ключей и подписей; контракт — первым.

**Scale/Scope**: одна машина одного человека, несколько устройств; соединений на устройство — единицы.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Принцип | Проверка | Итог |
|---|---|---|
| I. Приватность | Новых данных за пределами устройства нет; сервер видит открытый ключ устройства, как и сегодня. Логи — без токенов, ссылок, ключей и подписей (FR-022); onion-адреса — меткой, как сегодня. Семя устройства передаётся модулю в процессе и обнуляется. | ✅ |
| II. Спека — источник истины | В том же change-set'е: экраны 2.1 и 2.2 (`login.md`, `qr-scan.md` и оба корпуса) — формат ссылки v3, отказы разбора; `overview.md` — «не тот сервер» только по onion. | ✅ |
| III. Блюпринт | `ChannelSocket`/`ChannelHttpClient` — data-слой (`lib/data/remote/channel/`), `PairingLink` — `general`, модуль — пакет; DI, `RepositoryResult`, `LogRepository` — как везде. Обновляются `14-networking-and-auth.md`, `09-build-and-secrets-infra.md`, `01-stack-and-tooling.md`, `02-dependency-injection.md`, `04-data-layer.md`. Rust-модуль собирается на всех пяти платформах (Принцип III 1.4.0). | ✅ |
| IV. Дизайн-система | Новые строки — в существующих компонентах входа и баннеров. | ✅ |
| V. Языки | Документы — русский; код, коммиты — английский; микрокопия — EN + UK. | ✅ |
| VI. Паритет | Изменения экранов входа и баннера — на обеих ширинах, голдены mobile и desktop. | ✅ |
| VII. Контракт — закон | Слой канала и ссылка v3 вносятся в контракт первыми (`contracts/wire-channel.md`, `pairing-link-v3.md`); сервер и клиент — в этом change-set'е. Инварианты `client_backend/CLAUDE.md` сохранены; приём соединений меняется (обёртка слушателя), порядок остановки — тот же: слушатель закрывается первым. | ✅ |

Повторная проверка после дизайна: нарушений нет; два отступления — в Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/044-secure-channel/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── wire-channel.md          # дельта §1, §2, §3, §8A контракта v0
│   ├── pairing-link-v3.md       # формат ссылки
│   ├── ffi-channel.md           # C ABI канала и Dart-обёртка
│   ├── eidolon-vectors.json     # общие векторы Rust ↔ Go
│   └── link-vectors.json        # общие векторы ссылки Go ↔ Dart
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
packages/nox_tor/
├── rust/Cargo.toml                       # + eidolon-auth, cyphergraphy, ec25519, tokio-rustls
├── rust/rust-toolchain.toml              # + Linux-цели
├── rust/src/channel/{mod,tls,eidolon,registry,target}.rs   # НОВОЕ: канал
├── rust/src/lib.rs                       # + nox_chan_*; − nox_tor_bridge_secret
├── rust/src/bridge.rs                    # − петлевой мост; подстраховочное подключение к onion → channel/target.rs
├── rust/src/engine.rs                    # set_target без моста (ключ доступа — в хранилище Arti)
├── rust/tests/channel.rs                 # НОВОЕ: канал против локального TLS-сервера с Eidolon
├── hook/build.dart                       # Linux больше не пропускается
├── lib/channel.dart                      # НОВОЕ: привязки nox_chan_* и NoxChannelApi
├── lib/nox_tor.dart, lib/src/nox_tor_bindings.dart   # − мост
└── test/{hook_test,channel_test}.dart

lib/
├── data/remote/channel/channel_socket.dart        # НОВОЕ: Socket поверх NoxChannel
├── data/remote/channel/channel_http_client.dart   # НОВОЕ: вместо pinned_http_client.dart
├── data/remote/channel/channel_failure.dart       # НОВОЕ: виды отказа
├── data/remote/pinned_http_client.dart            # УДАЛЯЕТСЯ
├── general/pairing/server_pin.dart                # УДАЛЯЕТСЯ
├── general/pairing/pairing_link.dart              # версия 3
├── general/pairing/device_keys.dart               # − подпись challenge
├── data/remote/socket/{socket_channel_factory,nox_socket_client,server_frame}.dart
├── data/remote/api_client.dart
├── data/remote/interceptor/auth_interceptor.dart  # 401 больше не выход
├── data/sync/connection/{direct_prober,connection_path_selector}.dart
├── data/sync/{live_session_starter,live_identity_handshake}.dart
├── data/repository/app/{session_repository_impl,auth_repository_impl}.dart
├── data/service/tor/native_tor_service.dart       # − мост
├── presentation/pages/login_page/…                # отказы разбора ссылки
├── di/…                                           # регистрация ChannelHttpClient и NoxChannelApi
└── l10n/app_{en,uk}.arb
macos/Runner/{DebugProfile,Release}.entitlements   # − network.server (мост)

test/ — зеркально: pairing_link_test (векторы), channel_socket_test (НОВЫЙ), channel_http_client_test (НОВЫЙ),
        direct_prober_test, connection_path_selector_test, nox_socket_client_test, live_session_starter_test,
        live_identity_handshake_test, session_repository_impl_test, auth_repository_impl_test, login_bloc_test,
        auth_interceptor_test; − server_pin_test, pinned_http_client_onion_test, transports_are_pinned_test,
        server_pin_callback_test; голдены login_page (mobile + desktop)

client_backend/
├── internal/eidolon/{eidolon.go,eidolon_test.go,testdata/vectors.json}   # НОВОЕ
├── internal/server/channel.go, channel_test.go    # НОВОЕ: обёртка слушателя
├── internal/server/tls.go                         # технический сертификат; − пиннинг
├── internal/server/{server,ws,handlers,pairing,files,onion,status,status_page,pairing_link}.go
├── internal/store/serverkey.go                    # Ed25519
├── internal/protocol/frames.go
├── migrations/001_init.sql
├── cmd/smoke/main.go                              # Eidolon-клиент, ссылка v3
└── internal/server/*_test.go, internal/store/*_test.go

docs/
├── client-backend/protocol/contract-draft.md      # §1, §2, §3, §8A, ошибки
├── client-backend/architecture/{transport,authentication}.md, client-backend/README.md, README.md
├── blueprints/mobile/{01,02,04,09,10,14,16}-*.md
├── blueprints/client-backend/README.md
├── design/spec/screens/{login,qr-scan,devices,file-view}.md, design/spec/overview.md
├── design/system/nox-mobile-screens/screens/{2-1-login,2-2-qr-scan,7-8-devices}.md
├── design/system/nox-desktop-screens/screens/{04-login,06-qr,09-devices}.md
├── client-backend/demo-runbook.md, scripts/demo-stand.sh
CLAUDE.md, client_backend/CLAUDE.md                # разделы TLS/пиннинг/мост
```

**Structure Decision**: модуль канала живёт в существующем пакете `nox_tor` (R17); в Dart — новая папка `lib/data/remote/channel/` на месте `pinned_http_client.dart`; на сервере — новый пакет `internal/eidolon` и обёртка слушателя `internal/server/channel.go`.

## Complexity Tracking

| Отступление | Почему нужно | Почему проще не годится |
|---|---|---|
| Между 044 и 045 спаривание нового устройства через onion недоступно: в ссылке v3 нет одноразового ключа доступа Tor, поэтому одноразовые ключи onion-приглашений уходят уже в 044, а приглашение подписано «только дома» | Ключи доступа Tor целиком убирает 045; переносить одноразовый ключ в новый формат ради одной фичи — работа на выброс | Обе фичи в одной ветке и уходят вместе; прямое спаривание и связь через Tor спаренных устройств работают |
| Tor на Linux в 044 выключен, хотя модуль с Arti там уже собирается | Включение Tor на Linux — в объёме 045 по трекеру, вместе с `Use Tor` | Модуль канала нужен на Linux уже сейчас (прямой путь); путь через Tor на Linux проверяется вместе с переделкой Tor |
| Пакет называется `nox_tor`, хотя в нём весь канал | Переименование пакета, ассета и фреймворков — механика без пользы для фичи | Риск сломать сборку пяти платформ ради имени |
