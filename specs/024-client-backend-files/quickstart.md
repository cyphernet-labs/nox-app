# Quickstart: локальная проверка фичи 024

Валидационный сценарий «файловая цепочка работает end-to-end» (DoD фазы). Предпосылки — как в 022/023 (`go build -o noxd .`, websocat, curl). Цель по SC-007: ≤10 минут от чистой сборки.

## Подготовка

```bash
cd client_backend
go build -o noxd . && ./noxd -addr 127.0.0.1:8080 -db /tmp/nox-smoke-024.db
# каталог байтов по умолчанию: /tmp/nox-smoke-024.db-files (флаг -files / NOX_FILES)
dd if=/dev/urandom of=/tmp/probe.bin bs=1m count=10   # тестовый файл 10 МБ
```

Терминалы 1 (Anna) и 2 (Bob): websocat + `session.hello`; Anna создаёт чат (`CID`).

## Смоук Е — файловая цепочка

**Отправка (история 1), терминал Anna:**

```bash
{"id":10,"cmd":"file.uploadBegin","data":{"name":"probe.bin","size":10485760,"mime":"application/octet-stream"}}
# ← {"file_id":"<FID>","upload_url":"/files/<UT>","upload_token":"<UT>","max_attachment_bytes":104857600}
```

Заливка байтов (обычный терминал):

```bash
curl -sS -X PUT --data-binary @/tmp/probe.bin http://127.0.0.1:8080/files/<UT> -o /dev/null -w '%{http_code}\n'   # → 204
```

Снова Anna — сообщение-вложение без текста:

```bash
{"id":11,"cmd":"message.send","data":{"chat_id":"<CID>","client_message_id":"f1","attachment":{"file_id":"<FID>"}}}
# ← эхо с attachment{file_id,name,size,mime,expires_at}; у Bob — message.new с тем же объектом
{"id":12,"cmd":"chats.list","data":{"page":1,"page_size":10}}
# ← превью чата = "probe.bin" (нет текста → имя файла)
```

**Скачивание с докачкой (история 2), терминал Bob:**

```bash
{"id":20,"cmd":"file.downloadBegin","data":{"file_id":"<FID>"}}
# ← {"download_url":"/files/<DT>","download_token":"<DT>"}
```

```bash
curl -sS http://127.0.0.1:8080/files/<DT> -o /tmp/got.bin && cmp /tmp/probe.bin /tmp/got.bin && echo identical
# Докачка: новый токен (<DT2>), затем Range со второй половины:
curl -sS -r 5242880- http://127.0.0.1:8080/files/<DT2> -o /tmp/tail.bin -w '%{http_code}\n'   # → 206
cmp <(tail -c 5242880 /tmp/probe.bin) /tmp/tail.bin && echo resumed
```

**Панель файлов (история 3):** Anna шлёт пару текстовых сообщений и ещё одно вложение, затем:

```bash
{"id":30,"cmd":"chat.files","data":{"chat_id":"<CID>","limit":10}}
# ← только записи-вложения (file_id, name, size, mime, expires_at, message_id, seq), новые к старым порциями
```

## Негативные проверки

```bash
{"id":40,"cmd":"file.uploadBegin","data":{"name":"big","size":999999999999,"mime":"x"}}   # → payload_too_large
{"id":41,"cmd":"file.downloadBegin","data":{"file_id":"f_missing"}}                        # → not_found
{"id":42,"cmd":"message.send","data":{"chat_id":"<CID>","client_message_id":"nn"}}         # ни body, ни attachment → invalid_request
{"id":43,"cmd":"message.send","data":{"chat_id":"<CID>","client_message_id":"du","attachment":{"file_id":"<FID>"}}}  # файл уже привязан → invalid_request
curl -s -X PUT --data-binary @/tmp/probe.bin http://127.0.0.1:8080/files/<UT> -o /dev/null -w '%{http_code}\n'      # повтор использованного токена → 404
```

Заливка больше заявленного размера → 413, файл не сохраняется. Повтор `message.send` с тем же `client_message_id` → прежнее эхо с тем же вложением, события нет.

## Автоматическая валидация

```bash
cd client_backend
gofmt -l .            # пусто
go vet ./...
go test -race ./...   # зелёные, включая blob и files-интеграцию
```
