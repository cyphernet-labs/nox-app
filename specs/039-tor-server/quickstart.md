# Quickstart: проверка фазы 039

Как убедиться, что сервер в сети Tor работает. Формы на проводе — [contracts/wire-additions.md](./contracts/wire-additions.md), модель — [data-model.md](./data-model.md).

## Что нужно

- Go 1.27 и репозиторий на ветке `039-tor-server`.
- tor 0.4.9 или новее:
  - **macOS:** `brew install tor` или tor из Tor Expert Bundle. Бинарь из комплекта не подписан, и Apple Silicon его убивает, поэтому перед запуском — `codesign --force -s - tor` и то же для `libevent-*.dylib` рядом;
  - **Linux:** пакет ОС, если он не старее 0.4.9, иначе репозиторий Tor Project (deb.torproject.org);
  - **Windows:** `tor.exe` из Tor Expert Bundle рядом с `noxd.exe`.
- Доступ машины к сети Tor.

## 1. Гейт Go — всегда

```sh
cd client_backend
gofmt -l .            # пусто
go vet ./...
go test -race ./...   # тесты с настоящим Tor здесь пропускаются
```

## 2. Сквозная проверка через настоящий Tor

```sh
cd client_backend
NOX_TOR_TEST_BIN=/путь/к/tor go test -race -run 'TestOnion' -v ./internal/server/ -timeout 15m
```

Тест поднимает сервер с Tor и проверяет по сети Tor:

- устройство с ключом доступа подключается по onion-адресу, проходит пин, здоровается, отправляет сообщение и файл (SC-001);
- клиент без ключа не подключается (SC-002);
- после отзыва устройства его ключ не открывает соединение (SC-004);
- onion-адрес не меняется после перезапуска сервера (SC-003).

Длится от одной до нескольких минут: подключение к сети и публикация адреса.

Claim через onion (SC-005) через настоящую сеть не проверяется: сервер, который ещё не забран, onion-адреса не публикует — ключей нет. Отказ на onion-входе и целый после него токен проверяют тесты onion-входа без сети (`onion_entry_test.go`, `pairing_onion_test.go`).

## 3. Руками: сервер с Tor

```sh
cd client_backend && go build -o noxd . 
./noxd -addr 0.0.0.0:8080 -db /tmp/nox039.db -tor-bin /путь/к/tor
```

Ожидается:

1. В журнале — запуск tor, его версия и ход подключения. Onion-адреса в журнале нет (SC-012).
2. `http://127.0.0.1:8081` — страница статуса. До claim — ссылка и QR, как раньше. После claim — блок Tor: версия, вердикт сети, подключение, «не опубликован: нет устройств с доступом» (FR-027).
3. Спаривание с ключом доступа делает сквозной тест из п. 2: `cmd/smoke` ключей доступа не знает. Пока ключей нет, страница пишет `Not published: no device has access yet`.

## 4. Руками: без Tor

```sh
./noxd -addr 0.0.0.0:8080 -db /tmp/nox039.db -tor=false    # Tor выключен
./noxd -addr 0.0.0.0:8080 -db /tmp/nox039.db -tor-bin /нет  # tor не найден: явный путь окончателен, PATH не проверяется
```

Прямой путь работает как до фазы; страница называет причину (SC-006).

## 5. Совместимость с нынешним приложением

```sh
fvm flutter test test/data/remote/socket/nox_socket_client_test.dart test/data/sync/
```

Ответ на приветствие с `addresses` и событие `server.addresses` нынешний клиент проходит без изменений (SC-011). Перед коммитом, затрагивающим Dart, — `make gate` и `make golden-verify`.

## 6. Падение сервера не оставляет tor

```sh
./noxd -db /tmp/nox039.db -tor-bin /путь/к/tor &   PID=$!
sleep 20; kill -9 $PID; sleep 30; pgrep -fl "nox039.db-tor" || echo "tor ушёл"
```

Ожидается «tor ушёл» (SC-007). В спайке tor уходил за 2 секунды.
