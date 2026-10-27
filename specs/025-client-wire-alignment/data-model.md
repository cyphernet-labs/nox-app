# Data Model: client-wire-alignment (фаза 025)

Дельты моделей по слоям. Конвенция дат: домен — `DateTime` (local), Sembast — ISO-8601 UTC-строки (лексикографика = хронология, как сегодня), **wire — unix-секунды** (int, контракт §1); коэрция — только в мапперах.

## Домен

| Модель | Дельта |
|---|---|
| `MessageModel` | + `required int seq` (глобальный номер журнала; оптимистичные записи — `kPendingSeq`); остальное без изменений (`status`, `isSystem` — устройство-локальные) |
| `MessageAttachment` | + `String? mime`, + `DateTime? expiresAt`; `type` остаётся (выводится из расширения `name` при маппинге с провода) |
| `MimeTypes` (NEW) | таблица `расширение → mime` (`forFileName` / `forExtension` / `extensionOf`, неизвестное → `application/octet-stream`): по §7 mime выводит **клиент**, пикер байты не читает |
| `ChatModel` | + `DateTime? createdAt`, + `String? createdByLabel` (несёт wire; будущий генезис-рендер); `unreadCount` остаётся локальным |
| `ServerLimits` (NEW) | `{int maxMessageBytes, int maxAttachmentBytes, int maxFrameBytes}` + const контрактные дефолты; доступ через `AppConfigRepository.limits` |
| `PageMetadata` | `{required int total, int? nextPage}` → `{required bool hasMore, int? nextPage}` (`nextPage` — только страничный путь чатов) |
| `GetMessagesConfig` | `{chatId, page}` → `{chatId, int? beforeSeq, int limit}`; фабрики `tail(chatId)` / `olderThan(chatId, beforeSeq)`; `pageSize` остаётся 20 |
| `RepositoryException` | + `invalidRequest, nameTaken, payloadTooLarge, attachmentGone, rateLimited, unsupportedSchema`; маппер `RepositoryException.fromWireCode` (неизвестный → `internal`) |
| `SyncRepository` (NEW) | `getCursor() → int`, `advanceCursor(int seq)` (монотонный max, проверка-и-запись в одной транзакции DAO), `clear()` |

## Sembast (все новые поля — необязательные, паттерн `attachmentLocalPath`)

| Entity | Дельта |
|---|---|
| `MessageEntity` | + `int? seq`, + `String? attachmentMime`, + `int? attachmentExpiresAt` (unix) |
| `ChatEntity` | + `int? createdAt` (unix), + `String? createdByLabel` |
| `sync` store (NEW) | одна запись `state`: `{since: int}`; `SyncDao {readSince, writeSince, advanceSince (транзакционный max), cleanData}` |

`MessageDao._sortChrono` → сортировка по `seq`; тайбрейки — `sentAt`-строка, затем `id` (порядок тотальный: `sent_at` на проводе с точностью до секунды, поэтому одинаковые метки времени не должны переставлять записи против их `seq`). Фильтрация чата — по-прежнему в Dart (`field_rename: snake`).

**Легаси-строки (БД, обновлённая на месте).** Записи до 025 не имеют поля `seq` (маппер даёт `0`), а курсор `before_seq = 0` отрезал бы всё окно. `MessageRepositoryImpl._backfillLegacySeqIfNeeded` один раз на чат раздаёт им синтетические `seq` ниже минимального реального, в сохранённом порядке — нумерация чисто устройство-локальная, на провод не возвращается.

## Wire (переписаны 1:1, контракт §4–§7)

```json
Message  {"message_id", "seq", "chat_id", "author_id", "author_label",
          "client_message_id"?, "sent_at": unix,
          "body"?: {"type": "text", "text": "..."},
          "attachment"?: {"file_id", "name", "size", "mime", "expires_at": unix}}
Chat     {"chat_id", "name", "created_at": unix, "created_by_label",
          "last_message_preview", "last_activity_at": unix}
Страницы {"messages": [...], "has_more"} / {"chats": [...], "has_more"}
Ошибка   {"code", "message"}   // ResponseEntity.error: String? → ErrorWireEntity?
```

Ушли с провода: `status`, `is_system`, `unread_count`, `type`(категория вложения), `page/page_size/total`, ISO-строки времени. `client_message_id` парсится (обязателен в собственных сообщениях по §5) и до фазы 026 в домен не переносится.

`EntityConverter`: перерегистрация обеих цепочек — `ChatWireEntity`, `ChatsWireEntity`, `MessageWireEntity`, `MessagesWireEntity` (новые формы), `ItemEntity`/`ItemsEntity` без изменений (мёртвый verification-срез).

## Мапперы (единственные точки коэрции)

- `MessageWireMapper`: `sent_at` unix ↔ `DateTime`; `body.text` ↔ `text` (нет текста → null; тип не `text` → null); `attachment.mime`/`expires_at` ↔ домен; `FileType.fromExtension(name)`; `localPath` не с провода (реаттач эха в репозитории сохраняется).
- `ChatWireMapper`: `last_activity_at` unix ↔ `lastMessageAt`; `created_at`/`created_by_label` ↔ новые поля; `unreadCount` — 0 с провода (локальный).
- `MessageMapper`/`ChatMapper` (storage): + `seq`/`attachmentMime`/`attachmentExpiresAt`/`createdAt`/`createdByLabel`; `seq: entity.seq ?? 0`.

## Мок-генераторы

- `GetChatsApi`: `ChatsWireEntity{chats, has_more}`; чаты получают `created_at`/`created_by_label` (детерминированные).
- `GetMessagesApi`: сид-`seq = (chatIndex+1)*1000 + position` (R1); `MessagesWireEntity{messages, has_more}` с окном «хвост/`before_seq`»; вложение `att_spec` получает `mime: application/pdf` и `expires_at` далеко в будущем.
- `SendMessageApi` (+ `simulateIncoming`, генезис `seedCreatedChat`): runtime-`seq = nowMs*1000 + counter` (R1).

## Потоки записи курсора (моки)

`_seedChatIfEmpty` (max сидового `seq`), `sendMessage` (seq эха), `simulateIncoming` — все через `SyncRepository.advanceCursor`; `logout.afterMutate` → `clear()`.

## Инварианты

- Видимый порядок сообщений и чатов не меняется (сид-`seq` повторяет порядок по времени) — 216 голденов проходят без перегенерации.
- Старые Sembast-записи читаемы (все новые поля необязательные); легаси-`seq == 0` сортируется вторичным ключом.
- `unreadCount` и `status` не появляются на проводе; их локальная механика (increment в `simulateIncoming`, adopt в очереди) в 025 не меняется — пересчёт от `seq` последнего открытия — долг фазы 027/028 (§8.3).
