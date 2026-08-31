# Data Model: client-outbox

## Store `outbox` (Sembast)

Ключ записи — `client_message_id`. Это не украшение: уникальность ключа записи и есть гарантия, что повторная постановка того же сообщения не создаст вторую строку.

### `OutboxEntity` — `lib/data/entity/chat/outbox_entity.dart`

`@freezed` + `json_serializable`, **только базовые типы** (перечисление строкой, время строкой ISO-8601, вложение разложено плоскими полями) — тот же идиом, что `MessageEntity`; всякое приведение живёт в маппере.

| Поле | Тип | Смысл |
|---|---|---|
| `clientMessageId` | `String` | Ключ идемпотентности; дублирует ключ записи, чтобы декодированная сущность была самодостаточной |
| `chatId` | `String` | Чат назначения — отправка в другой запрещена (FR-011) |
| `ordinal` | `int` | Порядковый номер постановки; единственный ключ сортировки |
| `text` | `String?` | Текст; `null` при отправке только вложения |
| `createdAt` | `String` | ISO-8601, момент постановки |
| `status` | `String` | `OutboxStatus.name` — `pending` \| `error` |
| `attempts` | `int` | Сколько раз отправка не удалась — **любым** способом. Растит паузу следующей попытки, поэтому увеличивается и при повторяемом отказе, а не только при окончательном |
| `lastErrorCode` | `String?` | Код последнего отказа (§2.1); для диагностики, не для UI |
| `attachmentId` | `String?` | Дальше — плоское вложение, все поля `null`, когда его нет |
| `attachmentType` | `String?` | `FileType.name` |
| `attachmentName` | `String?` | |
| `attachmentSizeBytes` | `int?` | |
| `attachmentLocalPath` | `String?` | Путь на устройстве; на провод не уходит |
| `attachmentMime` | `String?` | |
| `attachmentExpiresAt` | `int?` | unix-секунды |

Новые поля объявляются **необязательными** (без `required`), чтобы записи, сделанные прежней версией, продолжали читаться, — правило, уже действующее для `MessageEntity`.

### `OutboxDao` — `lib/data/local/chat/outbox_dao.dart`

- `Future<List<OutboxEntity>> getAllSorted()` — все записи по возрастанию `ordinal`.
- `Future<List<OutboxEntity>> getByChat(String chatId)` — то же, отфильтровано **в Dart**.
- `Stream<List<OutboxEntity>> watch()` / `watch(String chatId)` — снимок store, сортировка и фильтрация в Dart.
- `Future<OutboxEntity> enqueue(OutboxEntity entity)` — в транзакции: вычисляет `ordinal = max + 1` и пишет запись; возвращает записанную.
- `Future<void> update(OutboxEntity entity)` — перезапись по ключу.
- `Future<void> remove(String clientMessageId)`.
- `Future<void> cleanData()` — опустошение store (вайп логаута).

Битая запись **пропускается**, а не роняет чтение — тот же охранник декодирования, что в `MessageDao`. Сортировка и фильтрация выполняются в Dart по декодированным сущностям: глобальный `field_rename: snake` делает `Finder` по camelCase-ключу молча пустым.

## Домен

### `OutboxStatus` — `lib/domain/model/chat/outbox_status.dart`

| Значение | Смысл |
|---|---|
| `pending` | Ждёт отправки или очередной попытки |
| `error` | Сервер отказал так, что повтор не поможет; ждёт человека |

Состояния `sending` нет намеренно: оно живёт ровно столько, сколько длится один `await` внутри сервиса, и персистировать его значило бы оставлять на диске мусор после падения процесса.

### `OutboxEntry` — `lib/domain/model/chat/outbox_entry.dart`

`@freezed` модель: `clientMessageId`, `chatId`, `ordinal`, `text?`, `attachment?` (`MessageAttachment`), `createdAt` (`DateTime`), `status` (`OutboxStatus`), `attempts`, `lastErrorCode?`.

### Переходы состояния

```text
        enqueue
           │
           ▼
      ┌─────────┐   отказ, который повтор не исправит   ┌───────┐
      │ pending │ ────────────────────────────────────▶ │ error │
      └─────────┘                                       └───────┘
        │  ▲  ▲                                          │    │
        │  │  └──────────── ручной повтор ───────────────┘    │
        │  └── повторяемый отказ: статус тот же, attempts +1   │
        │                                                     │
        ▼  сервер принял                        второй жест по пузырю
     запись удалена,                            запись удалена,
     сообщение лежит в `messages`               сообщения нет нигде
```

## Проекция в тред

`OutboxEntry` → `MessageModel` для отрисовки пузыря:

| Поле `MessageModel` | Источник |
|---|---|
| `id` | `clientMessageId` — тот же идентификатор, что и сегодня у оптимистичной строки |
| `chatId`, `text`, `attachment` | одноимённые поля записи |
| `authorId` / `authorLabel` | своя личность, разрешённая при открытии треда (`resolveIdentity`) |
| `sentAt` | `createdAt` |
| `status` | `pending` → `MessageStatus.pending`, `error` → `MessageStatus.error` |
| `seq` | не задан → 0-подобный сигнальный, как у оптимистичных строк сегодня |

Порядок в треде остаётся прежним: сортировка `allMessages` разводит совпадающие `seq`/время позицией в `outgoing`, а та теперь равна порядку `ordinal`.
