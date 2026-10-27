# Contracts: срез фазы 023

Источник — контракт v0 (`docs/client-backend/protocol/contract-draft.md`), §4–§6. Здесь — точный срез этой фазы с решениями Clarifications; при любом расхождении побеждает контракт (Принцип VII), а решения, которых в контракте не было, вносятся в него правкой в change-set реализации.

## Команды фазы

| Команда | `data` запроса | `data` ответа | Ошибки |
|---|---|---|---|
| `chats.list` | `{page, page_size, query?}` | `{chats: [Chat], has_more}` | `invalid_request` (page/page_size < 1), `internal` |
| `chat.get` | `{chat_id}` | `{chat: Chat}` | `invalid_request` (пустой chat_id), `not_found`, `internal` |
| `chat.rename` | `{chat_id, name}` | `{chat: Chat}` | `invalid_request` (правила `name`; пустой chat_id), `not_found`, `name_taken`, `internal` |
| `chat.nameAvailable` | `{name, exclude_chat_id?}` | `{available: bool}` | `invalid_request` (правила `name`), `internal` |
| `messages.list` | `{chat_id, before_seq?, limit}` | `{messages: [Message], has_more}` | `invalid_request` (пустой chat_id; limit < 1), `not_found`, `internal` |
| `message.send` | без изменений против 022 | без изменений | без изменений (в срезе 023 `body` обязателен — `attachment` появляется в 024) |

Все команды требуют выполненного `session.hello` (правило 022 «hello первым» действует без изменений).

## Правила пагинации (Clarifications 2026-08-27)

- Потолок порции — **100** и для `chats.list`, и для `messages.list`; больший запрошенный размер **молча ограничивается** потолком (не ошибка). Значения `< 1` → `invalid_request`.
- `chats.list`: `page` 1-базный; порядок `last_activity_at DESC, chat_id ASC` (стабильный tiebreaker); страница за пределами данных → пустой список + `has_more: false`.
- `messages.list`: обратная пагинация от хвоста; `before_seq` не задан → самые свежие; внутри порции — **по возрастанию `seq`**; `has_more: true` = существуют сообщения старше самой старой строки порции.
- `query`: трим по краям; пустая после трима → фильтра нет; вхождение подстроки в `name` **без учёта регистра, юникод-фолдинг** (единообразно с уникальностью имени).

## Правила `chat.rename` / `chat.nameAvailable`

- Правила поля `name` — как в 022: трим, непустое после трима, ≤64 рун, charset не ограничен; нарушение → `invalid_request`.
- Уникальность — глобальная, юникод-регистронезависимая, **с исключением самого `chat_id`** (rename) / `exclude_chat_id` (nameAvailable).
- **No-op**: имя после трима совпало с текущим **точно** (case-sensitive) → `ok` с текущей карточкой, события нет, журнал не растёт. Смена только регистра — обычное переименование с событием.
- Успешный rename **не меняет** `last_activity_at` и `last_message_preview` — строка не двигается в списке.
- `chat.nameAvailable` — подсказка без резервирования: авторитет — транзакция самой мутации.

## Событие фазы

| Событие | Payload | Примечания |
|---|---|---|
| `chat.updated` | полная wire-карточка `Chat` | эмитится **только** переименованием; идёт через общий журнал (`seq`), доставляется вживую и в реплее наравне с `chat.created`/`message.new`; пер-адресатных полей нет — кадр един для всех |

## Пер-адресатное правило `client_message_id` (§5)

Действует и для `messages.list`: в выдаче истории поле `client_message_id` присутствует только в сообщениях, автор которых — получатель ответа (идентичность этапа 1 — label). События `message.new` — без изменений против 022.
