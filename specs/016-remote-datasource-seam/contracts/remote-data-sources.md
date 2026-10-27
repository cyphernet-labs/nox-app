# Contract: RemoteDataSource interfaces

Four abstract, data-layer interfaces at `lib/data/remote/datasource/`. Each names exactly the network-boundary operations its repository already calls; signatures mirror the current `*Api.execute(...)` verbatim (no shaping — FR-002/FR-011).

```dart
// chat_remote_data_source.dart
abstract class ChatRemoteDataSource {
  Future<(List<ChatModel>, PageMetadata)> getChats({required GetChatsConfig config});
}

// chat_files_remote_data_source.dart
abstract class ChatFilesRemoteDataSource {
  Future<List<MessageAttachment>> getChatFiles({required String chatId});
}

// message_remote_data_source.dart  (aggregates read + send — FR-009)
abstract class MessageRemoteDataSource {
  Future<(List<MessageModel>, PageMetadata)> getMessages({required GetMessagesConfig config});
  Future<MessageModel> sendMessage({
    required String chatId,
    required String authorId,
    required String authorLabel,
    String? text,
    MessageAttachment? attachment,
  });
}

// item_remote_data_source.dart
abstract class ItemRemoteDataSource {
  Future<ResponseEntity<ItemsEntity>> getItems({required GetItemsConfig config});
}
```

## Behavioural contract

| Guarantee | Detail |
|-----------|--------|
| Pass-through | Each method's inputs, outputs, ordering, timing, and thrown errors are identical to the current generator call it forwards to. |
| No shaping | Return types are the exact tuples/types the generators return today (incl. `ResponseEntity<ItemsEntity>` for items). |
| No aggregation side-effects | `MessageRemoteDataSource` composes two generators but adds no cross-op logic — `getMessages` and `sendMessage` are independent forwards. |
| Contracts frozen | `RepositoryResult`, `PageMetadata`, and `BaseRepositoryHelper` error mapping are not referenced or altered by the interfaces — the repository still wraps the call in `execute(...)` exactly as before. |

## Mock implementations (`datasource/mock/`)

Each `MockXRemoteDataSource implements XRemoteDataSource` injects the existing generator(s) and forwards. Example:

```dart
@LazySingleton(as: ChatRemoteDataSource, env: [Environment.dev, Environment.prod, Environment.test])
class MockChatRemoteDataSource implements ChatRemoteDataSource {
  MockChatRemoteDataSource(this._api);
  final GetChatsApi _api;
  @override
  Future<(List<ChatModel>, PageMetadata)> getChats({required GetChatsConfig config}) => _api.execute(config: config);
}
```

`MockMessageRemoteDataSource` injects both `GetMessagesApi` and `SendMessageApi`. The generators keep `@lazySingleton` and their existing unit tests unchanged.

## Consumers (repositories)

- `ChatRepositoryImpl` depends on `ChatRemoteDataSource` + `ChatFilesRemoteDataSource`; `_seedIfEmpty`/`getChatFiles` call `.getChats`/`.getChatFiles`.
- `MessageRepositoryImpl` depends on `MessageRemoteDataSource`; `_seedChatIfEmpty`/`sendMessage` call `.getMessages`/`.sendMessage` (replacing two concrete deps with one interface).
- `ItemRepositoryImpl` depends on `ItemRemoteDataSource`; `getItems` calls `.getItems`.
