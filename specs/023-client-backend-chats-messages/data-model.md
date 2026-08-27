# Data Model: client-backend-chats-messages (фаза 023)

**Миграций нет.** Схема 001 из фазы 022 покрывает всю фазу: `chats` (с `name_ci` и уникальным индексом), `messages` (с UNIQUE `client_message_id`, UNIQUE `seq`, индексом `(chat_id, seq)`), `events` (AUTOINCREMENT `seq`).

## Сущности (wire, без изменений схемы)

### Chat — карточка чата (контракт §4)

| Поле wire | Колонка | Примечание |
|---|---|---|
| `chat_id` | `chats.chat_id` | PK |
| `name` | `chats.name` | отображаемое имя; правила поля из §4 |
| — | `chats.name_ci` | внутренняя: Go-кейс-фолдинг имени (`unicode.SimpleFold`); уникальность и `nameAvailable` |
| `created_at` | `chats.created_at` | unix-секунды |
| `created_by_label` | `chats.created_by_label` | генезис-строка клиента |
| `last_message_preview` | `chats.last_message_preview` | серверный снапшот для страниц `chats.list` |
| `last_activity_at` | `chats.last_activity_at` | меняют только сообщения и создание; **rename не меняет** |

### Message — сообщение (контракт §5)

Без изменений против 022; `attachment` появится в 024. `client_message_id` в выдаче `messages.list` подчиняется тому же пер-адресатному правилу §5, что и события: поле видит только автор.

### Событие `chat.updated` (контракт §6)

Строка `events` с `type = 'chat.updated'`, payload — полная wire-карточка `Chat` после переименования (маршалится в транзакции мутации, как `chat.created`). Пер-адресатных полей нет → один вариант кадра для всех.

## Запросы фазы (все параметризованные)

| Операция | Пул | Запрос (суть) |
|---|---|---|
| `ListChats` | read | `SELECT <chat cols> FROM chats ORDER BY last_activity_at DESC, chat_id ASC`; фильтр по подстроке и нарезка страницы — в Go (R1/R2) |
| `GetChat` | read | `SELECT <chat cols> FROM chats WHERE chat_id = ?` |
| `ListMessages` | read | `SELECT <msg cols> FROM messages WHERE chat_id = ? [AND seq < ?] ORDER BY seq DESC LIMIT ?+1` → разворот в Go (R3) |
| `NameAvailable` | read | `SELECT COUNT(1) FROM chats WHERE name_ci = ? [AND chat_id != ?]` (R5) |
| `RenameChat` | write (tx) | SELECT строки → no-op ветка → COUNT `name_ci` c исключением → UPDATE `name`,`name_ci` → INSERT `events(chat.updated)` (R4) |

## Инварианты данных, которые фаза обязана сохранить

- `seq` — глобальный, строго возрастающий; `chat.updated` получает номер из того же журнала (инвариант 5).
- Каждая мутация — ровно одна immediate-транзакция с событием внутри (инварианты 2–4); read-команды не открывают транзакций и не касаются writer-пула.
- `chats.name_ci` всегда равно Go-кейс-фолдингу от `name` — обе записи (`CreateChat`, `RenameChat`) обновляют пару атомарно.
- `messages` не мутируются этой фазой вовсе; `chats.last_activity_at`/`last_message_preview` мутируются только путями 022 (send/create).
