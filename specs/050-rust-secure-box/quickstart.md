# Quickstart: проверка 050 руками

## Что нужно

- Rust 1.93.1 с целью `wasm32-unknown-unknown` (`rustup target add wasm32-unknown-unknown` в `packages/rust_secure_box`);
- Go 1.27;
- FVM Flutter 3.44.1;
- macOS для гейтов и голденов.

## 1. RustSecureBox и его копия на сервере

```sh
cd packages/rust_secure_box && cargo test            # интерфейс и векторы
make box-verify                                      # сгенерированный Go-код совпадает со сборкой крейта
cd client_backend && go test -race ./internal/securebox/...
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
- `status_page_test` — строка о заглушке;
- `logs_test` — нет ключей, челленджей и подписей.

## 3. Приложение

```sh
make tor-test          # cargo test модуля (auth.rs против тестового сервера) + dart test пакета
make gate              # Dart: generate, format, analyze, test
make golden-verify     # UI не менялся — все голдены зелёные
```

## 4. Сквозная проверка с живым сервером

1. Собрать и запустить сервер:
   ```sh
   cd client_backend && go build -o noxd .
   ./noxd -addr 127.0.0.1:8443 -db /tmp/nox050/nox.db
   ```
   Затем `noxd unlock`. В журнале — предупреждение `RustSecureBox is a stub…`; на служебной странице — та же строка.
2. Взять ссылку и прогнать smoke:
   ```sh
   ./noxd link
   go run ./cmd/smoke '<ссылка>'
   ```
   Smoke спаривается, здоровается, создаёт чат и пишет сообщение через `/auth` и `/auth2`.
3. Пробы приложения:
   ```sh
   fvm flutter test test/live/channel_probe.dart --tags live
   ```
   Окружение — по комментарию в начале файла. Канал открывается; для чужого ключа сервера — `wrongServer`.
4. Приложение `stage` на macOS: спаривание ссылкой, сообщение, файл туда и обратно.

## 5. Переход (User Story 4)

1. Сервер и приложение сборки `security-rework` до 050 спарены, есть переписка.
2. Обновить сервер, открыть паролем. В журнале — `server key was made by another RustSecureBox: every device pairs again`. Служебная страница сразу показывает ссылку.
3. Обновить приложение и запустить. Оно один раз показывает экран спаривания: данные стёрты.
4. Спарить ссылкой со страницы. Видна прежняя переписка.

## 6. Подмена реализации (SC-005)

Проверка того, что настоящий RustSecureBox встанет без правок вокруг:

1. Во временной копии крейта заменить `stub.rs` реализацией на `ed25519-compact` (тот же код, что `ec25519` заказчика) — четыре функции с теми же сигнатурами.
2. В копии репозитория пересобрать через `build-wasm.sh` и прогнать:
   - `cargo test --test interface`;
   - `go test ./internal/securebox -run Interface`;
   - `go test ./internal/connauth ./internal/server -run Channel`;
   - `make tor-test`.
3. Ожидается:
   - всё проходит, кроме векторов заглушки;
   - `IsStub()` = `false`;
   - в `git diff` — только крейт и `boxwasm/`.

Проба 2026-10-15 (research R1) прошла этот путь для перевода `wasm2go`.
