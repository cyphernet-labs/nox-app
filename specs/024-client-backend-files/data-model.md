# Data Model: client-backend-files (фаза 024)

**Схема** — расширение единой миграции `001_init.sql` (правило владельца: до первого релиза вся схема живёт в одной миграции и правится на месте — развёрнутых баз ещё нет; append-only начинается с релиза). Добавленное:

```sql
CREATE TABLE files (
    file_id TEXT PRIMARY KEY,
    name TEXT NOT NULL CHECK (length(name) > 0),
    size INTEGER NOT NULL CHECK (size > 0),
    mime TEXT NOT NULL CHECK (length(mime) > 0),
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    uploaded INTEGER NOT NULL DEFAULT 0,
    message_id TEXT
) STRICT;

-- в CREATE TABLE messages добавлена колонка:
--   file_id TEXT REFERENCES files (file_id)

CREATE UNIQUE INDEX idx_messages_file ON messages (file_id) WHERE file_id IS NOT NULL;
```

## Сущности

### File — метаданные вложения (таблица `files`)

| Поле | Источник | Примечание |
|---|---|---|
| `file_id` | сервер (`f_` + hex) | ключ и имя байтов на диске |
| `name`, `size`, `mime` | `file.uploadBegin` | из объявления, не из байтов; имя в путях не участвует |
| `created_at` | сервер | момент объявления |
| `expires_at` | сервер | этап 1: `created_at` + 10 лет («бессрочно», поле обязано присутствовать) |
| `uploaded` | сервер | 1 только после полного приёма байтов и rename |
| `message_id` | сервер | NULL до `message.send`; заполняется в транзакции отправки |

Жизненный цикл: `объявлен (uploaded=0)` → `залит (uploaded=1)` → `привязан (message_id != NULL)`. Брошенные на первых двух стадиях дольше суток — зачищаются на старте.

### Attachment — wire-объект (контракт §5/§7)

`{file_id, name, size, mime, expires_at}` — собирается из строки `files` в транзакции `SendMessage` и входит в эхо, payload события и `messages.list`/`chat.files`. `Message` wire получает поле `attachment` (omitempty).

### Байты

`<files-dir>/<file_id>` (заливка во временный `<file_id>.part`, атомарный rename по завершении); каталог — флаг `-files`/`NOX_FILES`, дефолт `<db>-files`. Доступ только через `internal/blob` (`os.Root`).

### Токены (вне БД)

In-memory: token → {file_id, op ∈ {upload, download}, expires}; 10 минут; гасятся первым использованием; рестарт теряет их штатно.

## Запросы фазы

| Операция | Пул | Суть |
|---|---|---|
| `CreateUpload` | write (tx) | INSERT files (uploaded=0) |
| `MarkUploaded` | write (tx) | UPDATE files SET uploaded=1 WHERE file_id=? AND uploaded=0 |
| `FileByID` | read | SELECT строки files |
| `SendMessage` (расширение) | write (tx) | + проверка file: uploaded=1, message_id IS NULL → UPDATE files.message_id + messages.file_id; attachment в payload события |
| `ListChatFiles` | read | JOIN messages×files по chat_id, `before_seq`-паттерн 023 |
| `SweepOrphans` | write (tx) + blob | files с message_id IS NULL и created_at < now-24h → DELETE + удаление байтов |

## Инварианты данных

- Байты появляются на диске раньше, чем `uploaded=1` в БД; `uploaded=1` раньше, чем привязка к сообщению. Обратных состояний не существует.
- Один `file_id` — максимум одно сообщение (частичный UNIQUE), навсегда.
- Payload события `message.new` самодостаточен: объект вложения зашит в него при записи, replay не делает JOIN.
- `messages` и `chats` фазы 022–023 не меняют семантику; `chat.files` — чистая проекция.
