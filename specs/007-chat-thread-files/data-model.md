# Data Model — Этап M4 (Лента чата и файлы)

Phase 1. Domain-сущности messages/files-вертикали + BLoC-состояния + визуальный вокабуляр состояний. Все модели — `@freezed` (как `ChatModel`: только `.freezed.dart`, без JSON в UI-фазе — мок-данные). `domain` остаётся import-free.

## Domain — модели

### `MessageModel` (`lib/domain/model/chat/message_model.dart`)
Сообщение ленты (5.2). Принадлежность/группировка — по `authorId`.

| Поле | Тип | Заметки |
|---|---|---|
| `id` | `String` | стабильный id сообщения (для retry / ключей) |
| `chatId` | `String` | владелец-чат |
| `authorId` | `String` | стабильный ключ; own = `authorId == IdentityMockData.currentUserId` |
| `authorLabel` | `String` | текущий display-name (re-fetched на момент рендера; для author-header чужих) |
| `text` | `String?` | опц. (может быть только вложение) |
| `attachment` | `MessageAttachment?` | опц. одно вложение (locked `chat.md` — singular) |
| `sentAt` | `DateTime` | → `HH:mm` (bubble) + date-separator (лестница) |
| `status` | `MessageStatus` | только для своих (`pending`/`sent`/`error`); чужие → `none` |
| `isSystem` | `bool` (`@Default(false)`) | системная строка (`Chat created by {authorLabel}`); не считается сообщением |

### `MessageAttachment` (`lib/domain/model/chat/message_attachment.dart`)
Вложение сообщения / файл чата. Превью содержимого нет.

| Поле | Тип | Заметки |
|---|---|---|
| `id` | `String` | id вложения |
| `type` | `FileType` | маппинг типа → глиф/цвет (`noxFileIcon`/`noxFileColor`) |
| `name` | `String` | имя файла (ellipsis при переполнении) |
| `sizeBytes` | `int` | форматируется `FileSizeFormatter.format` → `2.4 MB` |

> 5.4 «Files collection» = `List<MessageAttachment>` чата (из `ChatRepository.getChatFiles`).

### Продвинутые enum'ы (PROMOTED в `domain`)
- `MessageStatus { none, pending, sent, error }` (`lib/domain/model/chat/message_status.dart`) — единый источник; `AppMessageBubbleWidget` импортирует отсюда.
- `FileType { image, video, audio, pdf, doc, sheet, text, archive, other }` (`lib/domain/model/file/file_type.dart`) — единый источник; мапперы `noxFileIcon`/`noxFileColor` остаются в `presentation/widgets/primitives/file_type.dart` (импортируют domain-enum).

### `FilesViewMode { list, grid }` (5.4)
Локальный enum переключателя List/Grid (presentation или domain — leaf-тип; держим рядом с `ChatCardBloc`/виджетом).

## Domain — конфиги и репозитории

### `GetMessagesConfig` (`lib/domain/repository/chat/get_messages_config.dart`)
`@freezed implements RepositoryConfig` (зеркалит `GetChatsConfig`).

| Поле | Тип | Заметки |
|---|---|---|
| `chatId` | `String` | обязателен |
| `page` | `int` | 1-based; `pageSize`/`defaultPage` константы; пагинация **старых** сообщений |

Фабрики: `firstPage({chatId})`, `nextPage({chatId, page})`. `static const pageSize`, `defaultPage = 1`.

### `MessageRepository` (`lib/domain/repository/chat/message_repository.dart`)
```
abstract class MessageRepository {
  Future<RepositoryResult<(List<MessageModel>, PageMetadata)>> getMessages({required GetMessagesConfig config});
  Future<RepositoryResult<MessageModel>> sendMessage({required String chatId, String? text, MessageAttachment? attachment});
  Future<void> clean(); // вызывается на logout
}
```

### `ChatRepository` (EDIT, `lib/domain/repository/chat/chat_repository.dart`)
Добавить chat-owned файлы (без пагинации):
```
Future<RepositoryResult<List<MessageAttachment>>> getChatFiles({required String chatId});
```

## Data — мок-источники (network-only)

| Источник | Файл | Поведение (мок) |
|---|---|---|
| `GetMessagesApi` | `data/remote/api/chat/get_messages_api.dart` | `@lazySingleton`. Детерминированная история per `chatId` (микс own/other по `IdentityMockData.currentUserId`, подряд-группы одного автора, ранний system-line `isSystem`), задержка ~150мс, пагинация старых наверх + `PageMetadata`. Один `chatId` → пустая история (Empty-state). |
| `SendMessageApi` | `data/remote/api/chat/send_message_api.dart` | `@lazySingleton`. one-shot POST → echo `MessageModel(status: sent)` после задержки; debug-исход → бросок/ошибка для `error`. |
| `GetChatFilesApi` | `data/remote/api/chat/get_chat_files_api.dart` | `@lazySingleton`. Список `MessageAttachment` per `chatId` (varied types/sizes incl. длинное имя); один `chatId` → пусто (Empty-files). |
| `MessageRepositoryImpl` | `data/repository/chat/message_repository_impl.dart` | `@LazySingleton(as: MessageRepository, env:[dev,prod,test])`, `BaseRepositoryHelper.execute` → `RepositoryResult`. `clean()` no-op. |
| `ChatRepositoryImpl` (EDIT) | `data/repository/chat/chat_repository_impl.dart` | реализовать `getChatFiles` via `GetChatFilesApi`. |

## Presentation — состояния BLoC

### `ChatThreadBloc` (sealed, зеркалит `ItemListBloc`/`ChatsListBloc`)
```
@freezed sealed class ChatThreadState:
  Initializing()
  Initialized(
    PagingState<String, MessageModel> pagingState,   // история (старые наверх)
    List<MessageModel> outgoing,                      // optimistic (pending/sent/error), новейшие
    String currentId,                                 // IdentityMockData.currentUserId
    MessageAttachment? draftAttachment,               // прикреплён, не отправлен
    bool isOffline,
    bool loadingInProgress,
  )
  Error()
```
- Computed-getters (extension): `items` (history), `nextPage`, `composedStream` ([...history, ...outgoing]), `hasDraft`, `sendActive` (text непустой || draftAttachment != null).
- События: `Initialize(chatId)` / `LoadOlder` (`sequential()`) / `MessageSent(text?, attachment?)` / `SendRetried(localId)` / `AttachmentPicked` (no-op picker → draft) / `AttachmentRemoved` / `SetScenario(debug)`.
- Загрузка истории: `getIt<MessageRepository>().getMessages(config)` внутри `executeLogic(onError:)`; `result.match(onData: applyPage, onError: …)`; re-check `state is Initialized` после `await`.
- Optimistic: `MessageSent` → добавить `MessageModel(status: pending)` в `outgoing` + очистить draft → `sendMessage` → `sent`/`error`; `SendRetried` повторяет по `localId`.

### `ChatCardBloc` (sealed)
```
@freezed sealed class ChatCardState:
  Initializing()
  Initialized(List<MessageAttachment> files, FilesViewMode viewMode, bool isOffline)
  Error()
```
- События: `Initialize(chatId)` / `ViewModeChanged(FilesViewMode)` / `SetScenario(debug)`.
- `getIt<ChatRepository>().getChatFiles(chatId)` внутри `executeLogic(onError:)`; Empty → `files: []`.

### 5.3 — без BLoC
`FileViewPage` (`StatefulWidget`): локальные поля `double _progress` (0..1), `bool _cached`, debug-`scenario`. Таймер-драйвен фейк-прогресс; `Save`/`Download` → no-op + snackbar.

## Визуальный вокабуляр состояний (мок + debug)

| Экран | Состояния | Источник |
|---|---|---|
| 5.2 Chat thread | Initial-loading · Empty (system-line + empty `chatBubble`) · Filled · Loading-older · Sending (`pending→sent`) · Send-error (`error`+retry) · Offline (`MaterialBanner`) · Fatal→3.1 | `ChatThreadBloc` + `ChatThreadScenario` (debug) |
| 5.3 File view | Loading (`LinearProgressIndicator` %, `Save` disabled) · Loaded (`Save` enabled) · Inline-error (snackbar+retry) · Fatal→3.1 | локальный state + debug |
| 5.4 Chat card | Initial-loading · Loaded-List · Loaded-Grid · Empty-files (`folderOpen`) · Offline/Inline-error (`MaterialBanner`) · Fatal→3.1 | `ChatCardBloc` + `ChatCardScenario` (debug) |

## Идентичность (мок)

`IdentityMockData` (`lib/general/mock/identity_mock_data.dart`): `static const String currentUserId` + `static const String currentLabel`. Используют `GetMessagesApi` (стамп `authorId`) и `ChatThreadBloc` (`currentId`); рекомендовано согласовать с `SettingsRootBloc` (7.1). Реальная идентичность — Фаза 2 (`// TODO(backend):`).

## Связи

- `ChatModel` (5.1) → `chatId` → `ChatThreadBloc.initialize(chatId)` (5.2) → `MessageModel.attachment` / `getChatFiles(chatId)` → `MessageAttachment` → 5.3 (`showFileView`).
- 5.2 имя/info → 5.4 (`showChatCard(chat)`); 5.4 файл → 5.3.
- `currentUserId` (мок) определяет own/other во всех bubble.
