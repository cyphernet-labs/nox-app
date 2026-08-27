# NOX client server (noxd)

Собственный сервер мессенджера NOX для малого круга (~10 человек): один WebSocket-канал команд (JSON-конверт, глобальный лог событий `seq`, догон по курсору `since`), REST-поверхность (`GET /health`), встроенный SQLite. Один статический бинарник без CGO.

Контракт провода — `docs/client-backend/protocol/contract-draft.md` (v0). Стадия 1: аутентификации нет — приветствие несёт `challenge`, но `device_key`/`signature` принимаются и игнорируются.

## Требования

- Go 1.27+ (`go version`)
- Для ручного смоука: `websocat` (`brew install websocat`) и `curl`

## Сборка и запуск

```bash
cd client_backend
go build -o noxd .
./noxd -addr 127.0.0.1:8080 -db /tmp/nox-smoke.db
```

При старте сервер применяет миграции (лог slog JSON в stderr) и начинает слушать. Проверка живости:

```bash
curl -s http://127.0.0.1:8080/health
# → {"status":"ok"}
```

### Флаги и переменные окружения

| Флаг | Env | По умолчанию | Назначение |
|---|---|---|---|
| `-addr` | `NOX_ADDR` | `127.0.0.1:8080` | Адрес прослушивания (`host:port`) |
| `-db` | `NOX_DB` | `nox.db` | Путь к файлу базы SQLite |
| `-files` | `NOX_FILES` | `<db>-files` | Каталог байтов вложений |

Флаг имеет приоритет над переменной окружения. Остановка — `Ctrl+C` (graceful shutdown: клиенты получают close-код going away, процесс завершается за ≤ 10 с).

## Смоук A — обмен вживую

Терминал 1:

```bash
websocat ws://127.0.0.1:8080/ws
# ← {"srv":{"schema_max":1,"challenge":"..."}}
{"id":1,"cmd":"session.hello","data":{"schema":1,"label":"Anna"}}
# ← {"id":1,"ok":true,"data":{"schema":1,"cursor":0,"limits":{...},"identity":{"id":"Anna","label":"Anna"}}}
{"id":2,"cmd":"chat.create","data":{"name":"smoke"}}
# ← {"id":2,"ok":true,"data":{"chat":{"chat_id":"<CID>",...}}}   <- скопировать CID
{"id":3,"cmd":"message.send","data":{"chat_id":"<CID>","client_message_id":"a1","body":{"type":"text","text":"hello"}}}
# ← эхо с message_id, seq и client_message_id
```

Терминал 2 (открыть **до** отправки следующего сообщения):

```bash
websocat ws://127.0.0.1:8080/ws
{"id":1,"cmd":"session.hello","data":{"schema":1,"label":"Bob"}}
```

Снова терминал 1:

```bash
{"id":4,"cmd":"message.send","data":{"chat_id":"<CID>","client_message_id":"a2","body":{"type":"text","text":"second"}}}
```

**Проверка:** в терминале 2 мгновенно (< 1 с) появляется `{"seq":N,"event":"message.new","data":{...}}` с полным сообщением.

Отправитель тоже получает event-кадры собственных сообщений (после эха). Кадр автора содержит `client_message_id`; кадры остальных получателей — нет (контракт §5).

**Идемпотентность:** повторить кадр `id:4` с тем же `client_message_id":"a2"` → эхо идентично первому, событие второй раз не приходит.

## Смоук B — обрыв и догон

1. В терминале 2 запомнить последний увиденный `seq` (= `S`), убить websocat (`Ctrl+C`).
2. Из терминала 1 отправить 2–3 сообщения (`a3`, `a4`, …).
3. Переподключить терминал 2 с курсором:

```bash
websocat ws://127.0.0.1:8080/ws
{"id":1,"cmd":"session.hello","data":{"schema":1,"label":"Bob","since":S}}
```

**Проверка:** в ответе — текущий `cursor`; следом досылаются **все** пропущенные события с `seq > S` по возрастанию. Клиент догнан, когда обработал событие с `seq ≥ cursor`; дальше поток live (проверить ещё одним сообщением из терминала 1). Дубликаты на границе реплея допустимы — клиент дедуплицирует по `seq`; потеря — нет. `since` без поля = без досылки (только live); `since` больше текущего `cursor` = пустая досылка.

## Смоук C — живучесть

- **Медленный клиент:** приостановить вывод в терминале 2 (`Ctrl+S`) и лить сообщения из терминала 1, пока не переполнится буфер соединения → соединение 2 закрывается кодом policy violation, терминал 1 продолжает получать эхо без задержки. `Ctrl+Q` возвращает вывод; переподключение с `since` досылает пропущенное.
- **Shutdown:** при живых соединениях нажать `Ctrl+C` в терминале сервера → клиенты получают close-код going away, процесс завершается ≤ 10 с.
- **Рестарт:** повторный запуск с той же `-db` стартует без ошибок, данные на месте (повторить смоук B с прежним `since`).

## Смоук Д — полный чат-сценарий (фаза 023)

Подготовка: Anna создаёт два чата и пишет в первый (`Kitchen` → CID1, `Общий` → CID2, сообщение `a1` в CID1). Между шагами — пауза ~1 с: активность имеет секундную гранулярность, и у строк, попавших в одну секунду, порядок в списке определяет `chat_id`, а не последовательность действий.

### Список и поиск

```bash
{"id":10,"cmd":"chats.list","data":{"page":1,"page_size":10}}
# ← оба чата; Kitchen первым (последняя активность — сообщение), has_more:false
{"id":11,"cmd":"chats.list","data":{"page":1,"page_size":10,"query":"общ"}}
# ← только "Общий" (регистронезависимо, кириллица)
{"id":12,"cmd":"chat.get","data":{"chat_id":"<CID2>"}}
# ← полная карточка чата
```

Порядок списка — по последней активности (новые сверху); превью строки — свёрнутый текст последнего сообщения. Порция больше 100 строк молча ограничивается сотней (`page_size` меньше 1 — ошибка `invalid_request`).

### История чата

Anna шлёт в CID1 ещё 4–5 сообщений (`a2`…), затем:

```bash
{"id":20,"cmd":"messages.list","data":{"chat_id":"<CID1>","limit":3}}
# ← 3 самых свежих по возрастанию seq, has_more:true; запомнить минимальный seq (= S)
{"id":21,"cmd":"messages.list","data":{"chat_id":"<CID1>","before_seq":S,"limit":10}}
# ← все более старые, has_more:false; вместе — вся история без дублей и пропусков
```

`before_seq` не задан — сервер отдаёт хвост (самые свежие). В выдаче Anna её сообщения несут `client_message_id`; тот же запрос от Bob — без этого поля (правило §5: ключ идемпотентности виден только автору). Повтор `message.send` с использованным `client_message_id` строки не добавляет — история показывает сообщение один раз.

### Переименование вживую

Bob держит соединение открытым; Anna:

```bash
{"id":30,"cmd":"chat.nameAvailable","data":{"name":"Общий"}}                             # ← available:false
{"id":31,"cmd":"chat.nameAvailable","data":{"name":"Общий","exclude_chat_id":"<CID2>"}}  # ← available:true
{"id":32,"cmd":"chat.rename","data":{"chat_id":"<CID2>","name":"Новый общий"}}
# ← ok с полной карточкой; у Bob мгновенно (< 1 с) кадр {"seq":N,"event":"chat.updated",...}
{"id":33,"cmd":"chats.list","data":{"page":1,"page_size":10}}
# ← порядок НЕ изменился: переименование не считается активностью
```

Уникальность имени — глобальная, без учёта регистра (включая кириллицу), с исключением самого чата. Переименование в то же самое имя — успех без события. После обрыва `chat.updated` досылается реплеем с `since` в общем порядке журнала.

## Смоук Е — файлы (фаза 024)

Байты живут в каталоге рядом с базой (`<db>-files`; флаг `-files` / `NOX_FILES`). Тестовый файл: `dd if=/dev/urandom of=/tmp/probe.bin bs=1m count=10`.

### Отправка вложения

Терминал Anna:

```bash
{"id":10,"cmd":"file.uploadBegin","data":{"name":"probe.bin","size":10485760,"mime":"application/octet-stream"}}
# ← {"file_id":"<FID>","upload_url":"/files/<UT>","upload_token":"<UT>","max_attachment_bytes":104857600}
```

Заливка байтов (обычный терминал):

```bash
curl -sS -X PUT --data-binary @/tmp/probe.bin http://127.0.0.1:8080/files/<UT> -o /dev/null -w '%{http_code}\n'   # → 204
```

Сообщение-вложение (текст необязателен, но хотя бы одно из двух — обязательно):

```bash
{"id":11,"cmd":"message.send","data":{"chat_id":"<CID>","client_message_id":"f1","attachment":{"file_id":"<FID>"}}}
# ← эхо с attachment{file_id,name,size,mime,expires_at}; у второго клиента — message.new с тем же объектом
{"id":12,"cmd":"chats.list","data":{"page":1,"page_size":10}}
# ← превью чата = "probe.bin" (нет текста → имя файла)
```

Токены одноразовые (10 минут): повторный `PUT` тем же токеном → 404. Заливка сверх заявленного размера → 413, меньше (обрыв) → 400 — в обоих случаях байты не сохраняются, цепочка начинается заново с `file.uploadBegin`.

### Скачивание с докачкой

Терминал Bob:

```bash
{"id":20,"cmd":"file.downloadBegin","data":{"file_id":"<FID>"}}
# ← {"download_url":"/files/<DT>","download_token":"<DT>"}
```

```bash
curl -sS http://127.0.0.1:8080/files/<DT> -o /tmp/got.bin && cmp /tmp/probe.bin /tmp/got.bin && echo identical
```

Докачка после обрыва: запросить новый токен (`<DT2>`) и передать Range со смещения — сервер отдаёт `206` и только остаток:

```bash
curl -sS -r 5242880- http://127.0.0.1:8080/files/<DT2> -o /tmp/tail.bin -w '%{http_code}\n'   # → 206
cmp <(tail -c 5242880 /tmp/probe.bin) /tmp/tail.bin && echo resumed
```

Использованный токен скачивания → 404. Файл с истёкшим сроком или физически пропавшими байтами → `attachment_gone` на `file.downloadBegin` (терминальное состояние экрана файла).

### Панель файлов чата

```bash
{"id":30,"cmd":"chat.files","data":{"chat_id":"<CID>","limit":10}}
# ← только записи-вложения {file_id,name,size,mime,expires_at,message_id,seq}, новые к старым
# порциями; пагинация как у истории: before_seq, потолок 100, порция по возрастанию seq
```

## Негативные проверки

На подключении, где `session.hello` уже выполнен:

```bash
{"id":9,"cmd":"nope","data":{}}                       # → ok:false, invalid_request
{"id":10,"cmd":"chat.create","data":{"name":"SMOKE"}} # → name_taken (имена уникальны без учёта регистра)
{"id":11,"cmd":"session.hello","data":{"schema":1}}   # повторный hello → invalid_request
```

На свежем подключении:

```bash
{"id":1,"cmd":"session.hello","data":{"schema":99}}   # → unsupported_schema
{"id":1,"cmd":"chat.create","data":{"name":"early"}}  # команда до hello → invalid_request
```

Команды фазы 023:

```bash
{"id":40,"cmd":"chats.list","data":{"page":0,"page_size":10}}               # → invalid_request
{"id":41,"cmd":"chat.get","data":{"chat_id":"c_missing"}}                   # → not_found
{"id":42,"cmd":"chat.rename","data":{"chat_id":"<CID2>","name":"KITCHEN"}}  # имя другого чата → name_taken
{"id":43,"cmd":"messages.list","data":{"chat_id":"<CID1>","limit":0}}       # → invalid_request
```

Команды фазы 024:

```bash
{"id":50,"cmd":"file.uploadBegin","data":{"name":"big","size":999999999999,"mime":"x"}}  # → payload_too_large
{"id":51,"cmd":"file.downloadBegin","data":{"file_id":"f_missing"}}                      # → not_found
{"id":52,"cmd":"message.send","data":{"chat_id":"<CID>","client_message_id":"nn"}}       # ни body, ни attachment → invalid_request
{"id":53,"cmd":"message.send","data":{"chat_id":"<CID>","client_message_id":"du","attachment":{"file_id":"<FID>"}}}  # файл уже привязан → invalid_request
```

## Автоматическая валидация

```bash
cd client_backend
gofmt -l .            # пусто
go vet ./...
go test -race ./...   # все пакеты зелёные
```
