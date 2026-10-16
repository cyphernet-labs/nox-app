# Quickstart: проверка 050 руками

## Что нужно

- Rust 1.93.1 с целью `wasm32-unknown-unknown` (`rustup target add wasm32-unknown-unknown` в `packages/rust_secure_box`);
- Go 1.27;
- FVM Flutter 3.44.1;
- macOS для гейтов и голденов.

## 1. RustSecureBox и его копия на сервере

Из корня репозитория:

```sh
(cd packages/rust_secure_box && cargo test)          # интерфейс и векторы
make box-verify                                      # сгенерированный Go-код совпадает со сборкой крейта
(cd client_backend && go test -race ./internal/securebox/...)
```

Ожидается:
- векторы проходят в обоих местах;
- `IsStub()` = `true`;
- интерфейс окружения `Xenv` в `boxwasm/box.go` — ровно `Xrsb_random`.

## 2. Сервер

```sh
cd client_backend && gofmt -l . && go vet ./... && go test -race ./...
```

Ключевые тесты:
- `connauth` — все строки таблицы отказов `contracts/auth-exchange.md`;
- `channel_test` — пределы входа охватывают `/auth`;
- `serverkey_test` — перевыпуск;
- `run_test.go`, `TestTheStubIsAnnouncedInTheLogAndOnThePage` — строка о заглушке в журнале и на странице;
- `logs_test` — нет ключей, челленджей и подписей.

## 3. Приложение

```sh
make tor-test          # cargo test модуля (auth.rs против тестового сервера) + dart test пакета
make gate              # Dart: generate, format, analyze, test
make golden-verify     # UI не менялся — все голдены зелёные
```

## 4. Сквозная проверка с живым сервером

1. Собрать и запустить сервер (каталог данных сервер не создаёт сам). Все команды раздела — из корня репозитория:
   ```sh
   (cd client_backend && go build -o noxd .)
   mkdir -p /tmp/nox050
   client_backend/noxd -addr 127.0.0.1:8443 -db /tmp/nox050/nox.db -status-addr 127.0.0.1:8081 &
   client_backend/noxd unlock -status-addr 127.0.0.1:8081
   ```
   В журнале — предупреждение `RustSecureBox is a stub…`; на служебной странице — та же строка.
2. Взять ссылку и прогнать smoke:
   ```sh
   client_backend/noxd link
   (cd client_backend && go run ./cmd/smoke '<ссылка>')
   ```
   Smoke спаривается, здоровается, создаёт чат и пишет сообщение через `/auth` и `/auth2`.
3. Пробы приложения:
   ```sh
   fvm flutter test test/live/channel_probe.dart --tags live --dart-define=link="$(client_backend/noxd link -status-addr 127.0.0.1:8081 | head -1)"
   ```
   Без `--dart-define=link=…` проба пропускается (SKIP) — это не прохождение. Канал открывается; для чужого ключа сервера — `wrongServer`.
4. Приложение `stage` на macOS: спаривание ссылкой, сообщение, файл туда и обратно.

## 5. Переход (User Story 4)

1. Сервер и приложение сборки `security-rework` до 050 спарены, есть переписка.
2. Обновить сервер, открыть паролем. В журнале — `server key was made by another RustSecureBox: every device pairs again`. Служебная страница сразу показывает ссылку.
3. Обновить приложение и запустить. Оно один раз показывает экран спаривания: данные стёрты.
4. Спарить ссылкой со страницы. Видна прежняя переписка.

## 6. Подмена реализации (SC-005)

Проверка того, что настоящий RustSecureBox встаёт без правок вокруг. Порядок — раздел «Как заменить заглушку» в `packages/rust_secure_box/README.md`.

1. Во временной копии репозитория заменить `src/stub.rs` реализацией на `ed25519-compact` (тот же код, что `ec25519` заказчика) с `default-features = false`: четыре функции с теми же сигнатурами.
2. Пройти шаги 2–4 README:
   - `cargo metadata --format-version 1 >/dev/null` в крейте и в `packages/nox_tor/rust` (новые зависимости попадают в оба `Cargo.lock`);
   - `RSB_IMPLEMENTATION=ed25519-v1 cargo test --test vectors -- --ignored write_vectors` (пишет три копии векторов);
   - `make box-wasm`.
3. Прогнать шаг 5 README:
   - `cargo test` в крейте;
   - `make box-verify`;
   - `cd client_backend && go build ./... && go test -race -timeout 30m ./...`;
   - `make tor-test`;
   - `make gate`.
4. Ожидается:
   - всё проходит;
   - `IsStub()` = `false`; строки о заглушке нет ни в журнале, ни на служебной странице;
   - в `git diff` — только крейт, три копии векторов, два `Cargo.lock` и `boxwasm/`.

Проба 2026-10-15 (research R1) прошла этот путь для перевода `wasm2go`.
