# Contracts: срез контракта v0 для фичи 022

Нормативный контракт один — [docs/client-backend/protocol/contract-draft.md](../../../docs/client-backend/protocol/contract-draft.md) (v0). Этот файл не дублирует его, а фиксирует **срез**, реализуемый фичей 022, и отличия этапа 1.

## Реализуется в 022

| Элемент | Контракт | Примечание среза |
|---|---|---|
| Кадры `srv` / команда / ответ / событие | §2 | Полностью; «ровно один ответ на `id`» |
| Коды ошибок | §2.1 | Подмножество: `invalid_request`, `name_taken`, `payload_too_large`, `internal`, `unsupported_schema` |
| `session.hello` + replay | §3 | Полностью, включая поле этапа 1 `label`, семантику первого подключения и правило «догнан»; `device_key`/`signature` принимаются и игнорируются. **Заглушка этапа 1: `identity.id` = label** (симметрично `author_id` в data-model; настоящий формат — за Q11) |
| `chat.create` | §4 | Правила `name` (trim, непустое, ≤64, регистронезависимая уникальность) |
| `message.send` | §5 | `body` обязателен (вложений в 022 нет); идемпотентность по `client_message_id`; эхо и `message.new` своих сообщений несут `client_message_id` |
| События `chat.created`, `message.new` | §6 | Полные wire-модели; свёртка превью §6 |
| `GET /health` | §1 | REST-поверхность этапа 1 |

## НЕ реализуется в 022 (границы)

- Остальные команды §4–§5 (`chats.list`, `chat.get`, `chat.rename`, `chat.nameAvailable`, `messages.list`, `chat.files`) и событие `chat.updated` — фаза 023.
- Файловая цепочка §7 (`file.uploadBegin`/`downloadBegin`, `PUT`/`GET /files/*`, `attachment` в `message.send`) — фаза 024.
- Весь §8 (спаривание/аутентификация, push, markRead, blob-`body`) — этап 2 / заблокировано (конституция VII).
- TLS/пиннинг — деплой-работы; этап 1 — loopback без TLS.

## Клиенты контракта в этой фазе

Единственный потребитель — websocat-сценарий владельца ([quickstart.md](../quickstart.md)). Flutter-приложение не интегрируется (клиентский трек — после 023).
