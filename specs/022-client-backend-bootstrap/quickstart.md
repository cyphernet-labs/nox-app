# Quickstart: локальная проверка фичи 022

Валидационный сценарий «фича работает end-to-end». Он же — основа README сервера (FR-011). Цель по SC-001: от чистого клона до успешного смоука ≤ 10 минут.

## Предпосылки

- Go 1.27+ (`go version`), websocat (`brew install websocat`) — на машине владельца уже установлены.
- Репозиторий на ветке фичи; рабочий каталог — `client_backend/`.

## Сборка и запуск

```bash
cd client_backend
go build -o noxd .
./noxd -addr 127.0.0.1:8080 -db /tmp/nox-smoke.db
```

Ожидаемо: лог старта (slog JSON) с применёнными миграциями; процесс слушает.

```bash
curl -s http://127.0.0.1:8080/health          # → признак живости, HTTP 200
```

## Смоук A — обмен вживую (история 1)

Терминал 1:

```bash
websocat ws://127.0.0.1:8080/ws
# ← {"srv":{"schema_max":1,"challenge":"..."}}
{"id":1,"cmd":"session.hello","data":{"schema":1,"label":"Anna"}}
# ← {"id":1,"ok":true,"data":{"schema":1,"cursor":0,"limits":{...},"identity":{"label":"Anna",...}}}
{"id":2,"cmd":"chat.create","data":{"name":"smoke"}}
# ← {"id":2,"ok":true,"data":{"chat":{"chat_id":"<CID>",...}}}   ← скопировать CID
{"id":3,"cmd":"message.send","data":{"chat_id":"<CID>","client_message_id":"a1","body":{"type":"text","text":"hello"}}}
# ← эхо с message_id, seq и client_message_id
```

Терминал 2 (открыть **до** отправки следующего сообщения):

```bash
websocat ws://127.0.0.1:8080/ws
{"id":1,"cmd":"session.hello","data":{"schema":1,"label":"Bob"}}
```

Снова терминал 1: `{"id":4,"cmd":"message.send","data":{"chat_id":"<CID>","client_message_id":"a2","body":{"type":"text","text":"second"}}}`

**Проверка:** в терминале 2 мгновенно (< 1 с, SC-002) появляется `{"seq":N,"event":"message.new","data":{...}}` с полным сообщением.

Отправитель тоже получает event-кадры собственных сообщений (после эха). Кадр автора содержит `client_message_id`; кадры остальных получателей — нет (контракт §5).

**Идемпотентность (SC-004):** повторить кадр `id:4` с тем же `client_message_id":"a2"` → эхо идентично, событие второй раз НЕ приходит, в базе одна строка.

## Смоук B — обрыв и догон (история 2)

1. В терминале 2 запомнить последний `seq` (= S), убить websocat (Ctrl+C).
2. Из терминала 1 отправить 2–3 сообщения (`a3`, `a4`, …).
3. Переподключить терминал 2 с курсором:

```bash
websocat ws://127.0.0.1:8080/ws
{"id":1,"cmd":"session.hello","data":{"schema":1,"label":"Bob","since":S}}
```

**Проверка (SC-003):** в ответе — текущий `cursor`; следом досылаются **все** пропущенные события с `seq > S` по возрастанию; после `seq ≥ cursor` клиент догнан, дальше — live (проверить ещё одним сообщением из терминала 1).

## Смоук C — живучесть (история 3)

- **Медленный клиент:** запустить `websocat -B 1 ...` (или просто приостановить чтение Ctrl+S в терминале 2), лить сообщения из терминала 1 до переполнения буфера → соединение 2 закрывается кодом policy violation, терминал 1 продолжает получать эхо без задержки (SC-006). Ctrl+Q возвращает вывод.
- **Shutdown (SC-005):** при живых соединениях нажать Ctrl+C в терминале сервера → клиенты получают close-код going away, процесс завершается ≤ 10 с; повторный запуск с той же `-db` стартует без ошибок, данные на месте (повторить смоук B с прежним `since`).

## Негативные проверки (edge cases спеки)

```bash
{"id":9,"cmd":"nope","data":{}}                      # → ok:false, invalid_request
{"id":10,"cmd":"chat.create","data":{"name":"smoke"}} # → name_taken (регистронезависимо: "SMOKE" тоже)
{"id":11,"cmd":"session.hello","data":{"schema":1}}   # повторный hello → invalid_request
{"id":12,"cmd":"session.hello","data":{"schema":99}}  # с нового соединения → unsupported_schema
```

Команда до `session.hello` на свежем соединении → `invalid_request`.

## Автоматическая валидация

```bash
cd client_backend
gofmt -l .            # пусто
go vet ./...
go test -race ./...   # зелёные, включая тесты replay/идемпотентности/shutdown
```
