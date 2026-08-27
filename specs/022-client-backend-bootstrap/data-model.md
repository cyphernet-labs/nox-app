# Data Model: Client-сервер — bootstrap этапа 1

**Phase 1.** Схема SQLite (миграция `001_init.sql`) + wire-модели среза. Wire-формы — дословно контракт v0 ([contract-draft.md](../../docs/client-backend/protocol/contract-draft.md) §4–§6); здесь — хранение и правила.

## Таблицы (все STRICT)

### `chats`

| Колонка | Тип | Ограничения |
|---|---|---|
| `chat_id` | TEXT | PRIMARY KEY (генерируется сервером) |
| `name` | TEXT | NOT NULL; CHECK непустое; уникальность **регистронезависимая** — UNIQUE-индекс по `lower(name)`; длина ≤64 валидируется хендлером (`invalid_request`) |
| `created_at` | INTEGER | NOT NULL (unix-секунды UTC) |
| `created_by_label` | TEXT | NOT NULL (label соединения-создателя; identity-заглушка этапа 1) |
| `last_activity_at` | INTEGER | NOT NULL; обновляется **только** сообщениями (rename в 023 его не тронет) |
| `last_message_preview` | TEXT | NOT NULL DEFAULT '' (свёртка по правилу контракта §6: одна строка, ≤120 символов) |

### `messages`

| Колонка | Тип | Ограничения |
|---|---|---|
| `message_id` | TEXT | PRIMARY KEY (генерируется сервером) |
| `seq` | INTEGER | NOT NULL UNIQUE — `seq` события `message.new` этого сообщения (глобальный, внутри чата разрежен) |
| `chat_id` | TEXT | NOT NULL REFERENCES `chats` |
| `author_id` | TEXT | NOT NULL (этап 1: technical stub = label; формат — за Q11, колонка переживёт этап 2) |
| `author_label` | TEXT | NOT NULL (денормализация по модели открытого пространства) |
| `client_message_id` | TEXT | NOT NULL; **UNIQUE** — ключ идемпотентности; повтор возвращает прежнее эхо |
| `sent_at` | INTEGER | NOT NULL (unix-секунды UTC) |
| `body` | TEXT | NOT NULL (JSON-объект `{"type":"text","text":…}` как непрозрачный текст; сервер внутрь не заглядывает — шов Q1) |

Индексы: `(chat_id, seq)` — выборки треда фазы 023; UNIQUE `client_message_id`.

### `events`

| Колонка | Тип | Ограничения |
|---|---|---|
| `seq` | INTEGER | PRIMARY KEY **AUTOINCREMENT** — глобальный строго возрастающий порядок; никогда не переиспользуется |
| `type` | TEXT | NOT NULL (`message.new` \| `chat.created`) |
| `payload` | TEXT | NOT NULL — **готовый JSON `data` события**, полная wire-модель сущности; replay отдаёт его байт-в-байт |

Единственный источник replay. Правила: запись события — в одной транзакции с мутацией (инвариант 3); никакого удаления/перенумерации (инвариант 5); `payload` собирается на записи, чтобы replay не зависел от последующих изменений сущностей.

## Жизненные циклы

- **Chat**: создан (`chat.create` → строка + событие атомарно) → активность обновляется сообщениями. Удаления не существует (продуктовая модель).
- **Message**: вставка + событие атомарно; повтор по `client_message_id` — no-op с прежним эхом. Статусы (`sent`/`pending`/`error`) — сущность клиента, в хранилище сервера их **нет**.
- **Connection** (in-memory, не в БД): `connected` (получил `srv`) → `hello_done` (подписан; replay при `since`) → `live`; терминальные: `slow_dropped` (переполнение буфера), `closed`. Повторный `session.hello` в том же соединении → `invalid_request`.

## Wire-модели среза (ссылки, не дубли)

- `Chat`, `Message` — контракт §4/§5 (в 022 `Message` без `attachment`; `client_message_id` присутствует в эхо и в `message.new` собственных сообщений).
- Кадры и коды ошибок — контракт §2/§2.1; из кодов в 022 задействованы: `invalid_request`, `name_taken`, `payload_too_large`, `internal`, `unsupported_schema`.
- Identity-заглушка — `label` из hello (контракт §3, поле этапа 1); в ответе hello `identity.id` = label (та же заглушка, что `author_id`; настоящий формат — за Q11).
