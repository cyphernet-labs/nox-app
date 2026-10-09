# Implementation Plan: Tor отдельной службой — адреса сервера, `Use Tor` и раздел «Связь»

**Branch**: `045-tor-service-addresses` (от `security-rework` после слияния 044, PR — в `security-rework`) | **Date**: 2026-10-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/045-tor-service-addresses/spec.md`

## Summary

Сервер перестаёт знать про Tor: уходят `internal/tor`, отдельный onion-вход и ключи доступа; onion-сервис публикует служба tor на машине сервера и ведёт его на основной порт. Сервер хранит в базе публичный и onion-адрес, задаваемые параметрами запуска (с памятью о последнем применённом значении) и кнопкой `Set` на служебной странице (`Host`, `Origin`, токен формы), и сразу сообщает их устройствам (`addresses.public`, `addresses.onion`, `server.addresses`).

Приложение получает `Use Tor` (по умолчанию выключен; Tor — только когда напрямую не достучаться), экран подключения после любой ссылки, раздел «Связь» в настройках и шесть понятных причин неудачи — в баннере «нет связи», в «Связи» и на экране подключения. Tor включается на Linux, Arti собирается с PoW (`hs-pow-full`), ключи доступа уходят из приложения и модуля.

## Technical Context

**Language/Version**: Dart 3.12 (Flutter `3.44.1`, FVM); Rust 1.93.1 (`packages/nox_tor`); Go 1.27 (`client_backend/`).

**Primary Dependencies**: Arti `=0.47.0` + `hs-pow-full` (без `keymgr`/`ephemeral-keystore`); канал 044 (`nox_chan_*`, `ChannelHttpClient`); Go stdlib (`crypto/sha3` для проверки onion-адреса) — новых зависимостей нет.

**Storage**: сервер — колонки адресов в `server_identity`, без `onion_seed` и `devices.access_key` (`001_init.sql` на месте); приложение — `ServerAddresses` в сейфе: `public`, `manualAddress`, `manualOnion`, `useTor`.

**Testing**: Go `go test -race` (адреса, параметры, форма, ссылки, отсутствие tor); Rust `cargo test` + сборка с PoW по целям; Dart `flutter_test`, `bloc_test`, голдены обеих ширин для экрана подключения, «Связи» и баннеров с причинами; сквозной прогон на macOS с отдельным tor.

**Target Platform**: приложение — пять платформ, Tor на всех (Linux включается); сервер — Linux, macOS, Windows.

**Project Type**: мобильное + десктопное приложение, нативный модуль, Go-сервер; меняется контракт v0 (§1, §3, `server.addresses`, §8A).

**Performance Goals**: адрес со страницы — у подключённых устройств за 5 с (SC-003); возврат на прямой путь — сразу при смене сети или за 2 мин (SC-002).

**Constraints**: с выключенным `Use Tor` — ни одного соединения через Tor (SC-006); сервер не порождает процесс tor (SC-005); логи без onion-адресов (метка, как сегодня).

**Scale/Scope**: одна машина, несколько устройств; адресов — единицы.

## Constitution Check

| Принцип | Проверка | Итог |
|---|---|---|
| I. Приватность | Onion-адрес хранится в сейфе и в логах заменяется меткой; `Use Tor` выключен по умолчанию — Tor не светится в сети без нужды. | ✅ |
| II. Спека — источник истины | Новые экраны и разделы — в `docs/design/spec/` и обоих корпусах в том же change-set'е; решение «путь выбирается сам» отменяется в `overview.md`. | ✅ |
| III. Блюпринт | `ConnectPage`/`ConnectBloc`, `ConnectionBody`/`ConnectionPage`/блок — presentation; настройки связи — data/domain, `RepositoryResult`, `LogRepository`; Rust-модуль на всех пяти. Обновляются блюпринты 14, 04, 05. | ✅ |
| IV. Дизайн-система | Новые экраны — на существующих компонентах (`AppOnboardingScaffoldWidget`, поля, `AppPrimaryButtonWidget`, `AppSettingsNavRowWidget`, `AppNoticeStripWidget`), значок из того же пакета Material Symbols. | ✅ |
| V. Языки | Документы — русский; код и коммиты — английский; микрокопия — EN + UK. | ✅ |
| VI. Паритет | Экран подключения и «Связь» — обе ширины, голдены mobile + desktop; баннеры 5.1, 5.2, 5.4 — обе ширины. | ✅ |
| VII. Контракт — закон | Дельта §1, §3, `server.addresses`, §8A — первой (`contracts/wire-addresses.md`); инварианты `client_backend/CLAUDE.md` 1 и 9 переписываются (tor уходит из процесса и из порядка остановки). | ✅ |

Повторная проверка после дизайна: нарушений нет; отступление — в Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/045-tor-service-addresses/
├── plan.md, research.md, data-model.md, quickstart.md
├── contracts/
│   ├── wire-addresses.md           # дельта контракта v0
│   ├── service-page-addresses.md   # форма Set
│   ├── connection-ui.md            # экраны, причины, строки EN/UK
│   └── ffi-tor.md                  # модуль без ключей доступа, PoW
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
client_backend/
├── internal/tor/                               # УДАЛЯЕТСЯ
├── internal/server/{server,onion,ws,client,addresses,pairing,pairing_link,handlers,status,status_page}.go
├── internal/server/address_settings.go         # НОВОЕ: проверка адресов, параметры запуска, Set
├── internal/store/{serverkey,accesskeys,identity,pairing}.go   # адреса в server_identity; − ключи доступа
├── internal/config/config.go                   # − -tor*, + -public-addr, -onion-addr
├── internal/protocol/frames.go                 # − device.setAccessKey
├── migrations/001_init.sql
└── cmd/smoke/main.go

packages/nox_tor/
├── rust/Cargo.toml                             # + hs-pow-full; − keymgr, ephemeral-keystore, tor-keymgr
├── rust/src/{lib,engine}.rs                    # − nox_tor_set_target/clear_target, хранилище ключей
├── rust/src/channel/target.rs                  # группа подстраховки на каждый onion-сервис
└── lib/{nox_tor.dart,src/nox_tor_bindings.dart}

lib/
├── domain/model/connection/{server_addresses,connection_problem,connection_status}.dart
├── domain/repository/connection/{server_addresses_repository,access_key_repository}.dart   # − access key
├── data/repository/connection/{server_addresses_repository_impl,connection_storage}.dart
├── data/sync/connection/{connection_path_selector,access_key_registrar,connection_status_service_impl}.dart
├── data/sync/{live_session_starter,live_identity_handshake,sync_service}.dart
├── data/remote/socket/{nox_socket_client,server_addresses_parser}.dart
├── data/repository/app/{auth_repository_impl,session_repository_impl}.dart
├── data/service/tor/{native_tor_service,tor_capability,nox_tor_api,fake_tor_service}.dart
├── presentation/pages/connect_page/            # НОВОЕ: экран подключения
├── presentation/pages/connection_page/         # НОВОЕ: раздел «Связь» (Body + Page + блок)
├── presentation/pages/{login_page,qr_scan_page,settings_root_page,chats_list_page,chat_card_page}/
├── presentation/widgets/chat/app_thread_view_widget.dart
├── l10n/app_{en,uk}.arb
assets/svg/icons/{lan,lan-fill}.svg             # значок раздела

test/ — зеркально; голдены connect_page, connection_page, баннеры с причинами (mobile + desktop)

docs/
├── client-backend/protocol/contract-draft.md
├── design/spec/screens/{connect,connection,login,qr-scan,devices}.md, design/spec/overview.md
├── design/system/nox-{mobile,desktop}-screens/screens/…  # новые и изменённые экраны
├── blueprints/mobile/{04,05,14}-*.md, client-backend/{README,demo-runbook}.md
CLAUDE.md, client_backend/CLAUDE.md, scripts/demo-stand.sh
```

**Structure Decision**: сервер — правка существующих пакетов и новый файл `address_settings.go`; приложение — две новые страницы в `presentation/pages/`, настройки связи — расширение `ServerAddresses`.

## Complexity Tracking

| Отступление | Почему нужно | Почему проще не годится |
|---|---|---|
| Между 045 и 046 claim через onion разрешён, а ссылка claim ещё без срока | Срок ссылки и её выпуск с машины — 046 | Обе фичи в одной ветке `security-rework` и уходят вместе; отдельно 045 не выпускается |
