# Data Model: client-live-exchange (фаза 026)

Дельты по слоям. Доменные модели чата и сообщения **не меняются** — их привела к контракту фаза 025; здесь появляются сущности соединения и синхронизации.

## Домен

| Модель | Дельта |
|---|---|
| `SessionPhase` (NEW) | enum `{disconnected, connecting, catchingUp, live}` — наблюдаемое состояние канала, понятие отдельное от «есть ли сеть у устройства» |
| `SessionPhaseService` (NEW) | `watchPhase() → Stream<SessionPhase>`, `phase → SessionPhase` (текущая) |
| `ServerIdentity` (NEW) | `{String id, String label}` — личность, которую сервер сообщает в приветствии (§3) |
| `SyncRepository` | + `getEpoch() → String?`, `setEpoch(String)` — отметка мира данных; `getCursor`/`advanceCursor`/`clear` остаются от 025 |
| `GetMessagesConfig` | + `static const int maxLimit = 100`; фабрики `tail`/`olderThan` клампят `limit` к нему (контрактный потолок §5) |

## Sembast

| Стор | Дельта |
|---|---|
| `sync` | запись `state` получает второе поле: `{since: int, epoch: String?}`. `epoch` — идентичность источника данных (`mock` либо `live:<apiUrl>`); при расхождении с текущей стор чатов, стор сообщений и `since` очищаются один раз |

Схема чатов и сообщений не меняется: серверные строки ложатся в те же `ChatEntity`/`MessageEntity`, что и мок-строки, — формы совпали в 025.

## Data-слой: транспорт

| Тип | Роль |
|---|---|
| `NoxSocketClient` (NEW) | Соединение и конверт: `connect()`, `send(cmd, data) → Future<ResponseEntity<Map>>` (корреляция по `id`, таймаут 10 с — §5), `events → Stream<ServerEvent>`, `phase → Stream<SessionPhase>`. Реконнект с backoff+джиттером, keepalive ping 25 с |
| `ServerEvent` (NEW) | `{int seq, String event, Map<String, dynamic> data}` — разобранный кадр события |
| `SyncService` (NEW) | Подписан на `events`: применяет `chat.created`/`chat.updated` в `ChatDao`, `message.new` в `MessageDao`, затем двигает курсор. Отбрасывает событие с `seq <= cursor` (дедупликация на границе догона) |

## Data-слой: датасорсы

| Интерфейс | Дельта |
|---|---|
| `ChatRemoteDataSource` | + `createChat({name})`, `renameChat({chatId, name})`, `isNameAvailable({name, excludeChatId})` — сервер авторитет по уникальности (§4). Мок получает те же методы с нынешним локальным поведением |
| `MessageRemoteDataSource` | `sendMessage` меняет форму: `{chatId, clientMessageId, text, attachment}` — `authorId`/`authorLabel` уходят (§5: автора знает сервер) |
| `RealChatRemoteDataSource` (NEW) | Поверх `NoxSocketClient`: `chats.list`, `chat.create`, `chat.rename`, `chat.nameAvailable` |
| `RealMessageRemoteDataSource` (NEW) | Поверх `NoxSocketClient`: `messages.list`, `message.send` |

## Конфигурация

| Что | Дельта |
|---|---|
| `AppConfig.apiUrl` | Перестаёт быть `null`: `config/stage.json` получает `"app.apiUrl": "http://127.0.0.1:8080"`; адрес сокета выводится из неё (`http→ws`, путь `/ws`) |
| DI | `Real*RemoteDataSource` регистрируются для `[Environment.dev]`, моки сужаются до `[Environment.prod, Environment.test]` — три шага по `specs/016-remote-datasource-seam/contracts/di-binding.md` |

## Переходы состояний

```
disconnected ──connect()──> connecting ──hello ok──> catchingUp ──seq >= cursor──> live
     ^                          |                         |                          |
     └────── обрыв / ошибка ────┴─────────────────────────┴──────────────────────────┘
```

- `connecting` → `catchingUp`: получен ответ на приветствие (в нём же — курсор сервера и личность).
- `catchingUp` → `live`: применено событие с `seq >= cursor` из приветствия; при `since == cursor` переход мгновенный (правило «догнан», §3).
- Любое состояние → `disconnected`: обрыв сокета, таймаут pong, ошибка приветствия. Далее — повтор с backoff.
- Индикация связи: `online = (phase == live)`; отдельного визуального состояния «догоняем» в этой фазе нет (см. research R3).
