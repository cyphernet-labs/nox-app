# Implementation Plan: RustSecureBox и проверка запросами /auth и /auth2

**Branch**: `050-rust-secure-box` | **Date**: 2026-10-15 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/050-rust-secure-box/spec.md`

## Summary

Проверка Eidolon (160 байт над экспортёром TLS) уходит. Её место занимают:

- **RustSecureBox** — крейт Rust `packages/rust_secure_box` из четырёх функций без состояния. Сейчас это заглушка на SHA-2: подпись своим ключом проходит, чужая — нет.
- **Обмен `POST /auth` → `POST /auth2`** по тому же соединению сразу после TLS 1.3.

Приложение. Rust-модуль `nox_tor` подключает RustSecureBox как обычную зависимость Rust и сам ведёт два HTTP-запроса. Только потом отдаёт поток в Dart. Ключ устройства создаёт RustSecureBox; Dart получает его через четыре новые функции C ABI `nox_box_*`.

Сервер. Тот же крейт собирается в WebAssembly. `wasm2go` — тот же инструмент, что у SQLite в `ncruces/go-sqlite3` — переводит его в Go-код только на стандартной библиотеке. Сгенерированный файл лежит в репозитории, поэтому сервер по-прежнему собирается с `CGO_ENABLED=0` без Rust. Обмен `/auth`/`/auth2` ведёт входной слушатель канала, там же, где сегодня Eidolon. Поэтому `http.Server` по-прежнему видит только прошедшие проверку соединения, а пределы входа и бюджет 30 с охватывают всю проверку.

Переход:

- сессия устройства, ключ которой сделан не текущим RustSecureBox, один раз уходит к спариванию;
- сервер, чей ключ сделан не текущим RustSecureBox, перевыпускает открытый ключ и отпускает все устройства, переписка остаётся;
- заглушку сервер узнаёт по пробному ключу и предупреждает о ней в журнале и на служебной странице.

Проба `wasm2go` на заглушке и на Ed25519 — в research R1.

## Technical Context

**Language/Version**:
- Rust 1.93.1 (тулчейн `packages/nox_tor/rust/rust-toolchain.toml`; для RustSecureBox — свой `rust-toolchain.toml` с целью `wasm32-unknown-unknown`);
- Go 1.27;
- Dart ≥3.12 / Flutter 3.44.1 (FVM).

**Primary Dependencies**:
- RustSecureBox: `sha2` 0.10 (заглушка), `getrandom` 0.3 (случайные байты в приложении). Оба уже в графе `nox_tor`.
- `nox_tor`: убираются `eidolon-auth`, `cyphergraphy`, `ec25519`; добавляются `rust_secure_box` (путь), `httparse` 1.10 и `serde_json` 1 (оба уже в графе через Arti).
- Сервер: новых прямых зависимостей нет. `wasm2go` v0.4.15 — инструмент генерации, запускается `go run …@v0.4.15` из скрипта и в `go.mod` не попадает.
- Dart: убирается `cryptography`.

**Storage**:
- Сейф устройства: новая запись `session.device_key` (JSON: закрытый и открытый ключ, base64); `session.device_secret` удаляется.
- База сервера: схема не меняется, `server_identity.private_key` теперь хранит закрытый ключ RustSecureBox.

**Testing**:
- `cargo test` для RustSecureBox и `nox_tor`, общие векторы;
- `go test -race ./...`: векторы на WebAssembly-копии, обмен через настоящий входной слушатель, перевыпуск ключа, предупреждение о заглушке;
- `make gate`, `make golden-verify` (UI приложения не меняется);
- `make tor-test`;
- живые пробы `test/live/*`, `cmd/smoke`.

**Target Platform**: приложение — iOS, Android, macOS, Windows, Linux; сервер — Linux, macOS, Windows (`CGO_ENABLED=0`).

**Project Type**: мобильное и настольное приложение плюс самостоятельный сервер; общая библиотека на Rust.

**Performance Goals**: дома соединение с проверкой — меньше 1 с (SC-006). Затраты по пробе: заглушка в Go — около 3 мкс на подпись; Ed25519 в Go через `wasm2go` — около 0,3 мс на проверку подписи.

**Constraints**:
- бюджет TLS и проверки на сервере — 30 с от приёма;
- тело запроса проверки — не больше 1 КиБ, весь этап проверки — не больше 16 КиБ;
- WebAssembly без импортов, кроме одного источника случайных байтов;
- ни закрытых ключей, ни челленджей, ни подписей в журналах.

**Scale/Scope**: один сервер одного человека. Затронуты:
- новый крейт;
- Rust-модуль (канал);
- около 10 Go-файлов сервера и его тесты;
- около 12 Dart-файлов;
- контракт, конституция, блюпринты, `CLAUDE.md` и архитектурные документы.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Принцип | Оценка |
|---|---|
| I. Приватность и E2EE | ✅ Закрытые ключи не покидают устройство и сервер; в журналах нет ключей, челленджей и подписей (FR-024). Граница E2EE (Q1) не затрагивается. Ослабление стойкости — заглушка — решение владельца, о нём предупреждает сервер (FR-022). |
| II. Спецификации — источник истины | ✅ Спецификация 050 описывает целевое состояние темы 1 (артефакт v41). Дизайн-корпус не меняется: экранов нет. |
| III. Блюпринт | ✅ Dart-код строится по `docs/blueprints/mobile/`: репозитории, `RepositoryResult`, DI. Блюпринты `01`, `02`, `04`, `09`, `10`, `14`, `16` правятся в том же наборе изменений (FR-023). Ключ — в сейфе «только это устройство» на всех пяти платформах. |
| IV. Дизайн-система | ✅ Не затронута. Строка о заглушке — на служебной странице сервера, это не UI приложения. |
| V. Языки | ✅ Документы — по-русски, код и коммиты — по-английски. Строка служебной страницы — по-английски. |
| VI. Паритет платформ | ✅ Канал и RustSecureBox — в Rust-модуле на всех пяти платформах; экранов нет. |
| VII. Контракт провода | ⚠ Нужна поправка нормативного текста. Принцип VII и «Рабочий режим» конституции называют проверку Eidolon. Порядок: (1) контракт §1, §2, §3, §8A, §9 — первым; (2) поправка конституции 1.4.0 → **1.5.0** (MINOR — замена механизма проверки, как в 1.4.0) через `/speckit-constitution`, с одобрения владельца; (3) код. Трекер `roadmap-security.md` уже содержит решения (тема 1, 2026-10-15). |

**Gate**: проходит при условии, что поправка конституции идёт первой задачей (Complexity Tracking).

**Повторная проверка после дизайна (Phase 1)**: дизайн не добавил ни прямой зависимости Go, ни миграции, ни нового экрана. Канал по-прежнему решает, кто на другом конце, до первого байта, который видит `http.Server` (R7). Нарушений нет; остаётся только поправка VII.

## Project Structure

### Documentation (this feature)

```text
specs/050-rust-secure-box/
├── spec.md
├── plan.md              # этот файл
├── research.md          # R1–R14
├── data-model.md        # ключи, челлендж, состояние проверки, записи сейфа и базы
├── quickstart.md        # проверка руками: стенд, переход, подмена реализации
├── contracts/
│   ├── rust-secure-box.md   # интерфейс: Rust API, C ABI WebAssembly, импорт случайных байтов
│   ├── auth-exchange.md     # POST /auth, POST /auth2 на проводе
│   ├── ffi-box.md           # nox_box_* и изменения nox_chan_open
│   └── rsb-vectors.json     # общие векторы (пишет тест крейта при реализации)
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
packages/rust_secure_box/           # НОВОЕ: RustSecureBox (заглушка), один код для приложения и сервера
├── Cargo.toml / Cargo.lock / rust-toolchain.toml
├── build-wasm.sh                   # cargo → .wasm → wasm2go → client_backend/internal/securebox/boxwasm; задаёт флаги сборки: стек 64 КиБ, пути CARGO_HOME без домашнего каталога
├── src/lib.rs                      # интерфейс: четыре функции, Error, размеры
├── src/stub.rs                     # заглушка — место, куда встаёт настоящая реализация
├── src/random.rs                   # случайные байты: система (натив) / импорт env.rsb_random (wasm)
├── src/wasm.rs                     # C ABI для WebAssembly: rsb_io, rsb_* (только wasm32)
└── tests/interface.rs, tests/vectors.rs, tests/data/rsb-vectors.json

packages/nox_tor/rust/
├── Cargo.toml                      # − eidolon-auth, cyphergraphy, ec25519; + rust_secure_box, httparse, serde_json
├── src/channel/eidolon.rs          # УДАЛЯЕТСЯ
├── src/channel/auth.rs             # НОВОЕ: клиент /auth → /auth2 поверх TLS
├── src/channel/{mod,tls,target,registry}.rs   # без экспортёра; seed → закрытый ключ устройства
├── src/secure_box.rs               # НОВОЕ: nox_box_* (C ABI для Dart)
├── src/lib.rs                      # экспорт nox_box_*; nox_chan_open с закрытым ключом
└── tests/channel.rs                # тестовый сервер отвечает на /auth и /auth2
packages/nox_tor/lib/
├── secure_box.dart                 # НОВОЕ: RustSecureBox (generateKeys, getChallenge, signChallenge, checkSignature)
├── src/secure_box_bindings.dart    # НОВОЕ
├── channel.dart, src/channel_{core,ffi,types}.dart   # deviceSeed → devicePrivateKey
└── test/secure_box_test.dart, test/channel_test.dart

client_backend/
├── internal/securebox/             # НОВОЕ
│   ├── securebox.go                # Box: пул экземпляров, случайные байты Go, ошибки, перехват ловушек, IsStub
│   ├── boxwasm/box.go + box.dat    # СГЕНЕРИРОВАНО wasm2go (не править)
│   └── securebox_test.go, testdata/rsb-vectors.json
├── internal/connauth/              # НОВОЕ (вместо internal/eidolon): Respond (сервер) и Initiate (тесты, smoke)
├── internal/eidolon/               # УДАЛЯЕТСЯ
├── internal/server/channel.go      # verify(): TLS → connauth.Respond
├── internal/server/{status,status_page,pairing_link,run…}.go   # ключи как []byte, строка о заглушке
├── internal/store/serverkey.go     # ключ от RustSecureBox, перевыпуск (FR-021)
└── cmd/smoke/main.go

lib/                                # Flutter
├── general/pairing/device_keys.dart                  # RustSecureBox вместо package:cryptography
├── data/repository/app/session_repository_impl.dart  # session.device_key, sweep session.device_secret
├── data/repository/app/auth_repository_impl.dart     # отставка сессии с ключом другого RustSecureBox
├── data/repository/device/device_repository_impl.dart
├── data/remote/channel/channel_http_client.dart, data/sync/{live_session_starter,connection/*}.dart
test/ …, test/live/{channel_probe,tor_live_probe}.dart, integration_test/tor_pairing_test.dart

docs/client-backend/protocol/contract-draft.md, .specify/memory/constitution.md,
docs/blueprints/{mobile/*,client-backend/README.md}, docs/client-backend/architecture/{authentication,transport}.md,
CLAUDE.md, client_backend/CLAUDE.md, client_backend/README.md, docs/README.md, docs/client-backend/roadmap-security.md,
Makefile (box-wasm, box-verify; tor-test зовёт cargo test крейта)
```

**Structure Decision**: RustSecureBox — отдельный крейт в `packages/`, потому что это «одна библиотека для приложения и сервера». Он не принадлежит ни `nox_tor`, ни `client_backend`:

- `nox_tor` берёт его зависимостью по пути;
- сервер получает его через `build-wasm.sh` в виде сгенерированного Go-кода.

Обмен `/auth`/`/auth2` на сервере — отдельный пакет `internal/connauth`, как раньше `internal/eidolon`: одна реализация для сервера, тестов и `cmd/smoke`.

## Порядок работ

1. **Документы-основания:** контракт (§1, §2, §3, §8A, §9, векторы); поправка конституции 1.5.0.
2. **RustSecureBox:** крейт, заглушка, интерфейсные тесты, векторы, сборка в wasm и перевод в Go; `internal/securebox` с тестом векторов.
3. **Сервер:** `internal/connauth`, входной слушатель, ключ сервера и перевыпуск, предупреждение о заглушке, тесты, `cmd/smoke`; удаление `internal/eidolon`.
4. **Rust-модуль:** `auth.rs`, `nox_box_*`, удаление Eidolon и экспортёра, тесты канала.
5. **Dart:** `package:nox_tor/secure_box.dart`; ключ устройства, отставка сессии, переименования, тесты; удаление `cryptography`.
6. **Документы-следствия:** блюпринты, оба `CLAUDE.md`, архитектура, README, трекер.
7. **Гейты и сквозная проверка:** `make gate`, `make golden-verify`, `go test -race`, `make tor-test`, `make box-verify`, живая проба и smoke против собранного `noxd`.

## Complexity Tracking

| Нарушение | Зачем | Почему проще не годится |
|---|---|---|
| Поправка нормативного текста конституции (Принцип VII, «Рабочий режим») до кода | Конституция называет Eidolon механизмом проверки; код 050 его убирает | Оставить текст как есть — значит держать норму, которой код противоречит: Принцип VII прямо требует, чтобы слой канала менялся сначала в контракте и нормах |
| Сгенерированный Go-файл (~120 КБ) в репозитории сервера | Сервер должен собираться без Rust и без cgo (FR-003) | Собирать WebAssembly при каждой сборке сервера — значит требовать Rust на машине владельца; среда выполнения WebAssembly (wazero) — новая прямая зависимость, а перевод уже проверен на SQLite |
