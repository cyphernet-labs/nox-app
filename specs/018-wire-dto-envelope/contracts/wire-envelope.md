# Contract: wire envelope for chat & message (S4)

## Data-source signatures (016 interfaces, changed)

```dart
// chat_remote_data_source.dart
abstract class ChatRemoteDataSource {
  Future<ResponseEntity<ChatsWireEntity>> getChats({required GetChatsConfig config});
}

// message_remote_data_source.dart
abstract class MessageRemoteDataSource {
  Future<ResponseEntity<MessagesWireEntity>> getMessages({required GetMessagesConfig config});
  // sendMessage(...) UNCHANGED — single POST echo, out of scope
  Future<MessageModel> sendMessage({required String chatId, required String authorId,
      required String authorLabel, String? text, MessageAttachment? attachment});
}
```

## Generator return types (mirror GetItemsApi)

```dart
GetChatsApi.execute({config})    -> Future<ResponseEntity<ChatsWireEntity>>
GetMessagesApi.execute({config}) -> Future<ResponseEntity<MessagesWireEntity>>
```

## Repo unwrap (mirror ItemRepositoryImpl.getItems)

```dart
final response = await _chatRemote.getChats(config: config);
final entity = response.data;
if (entity == null) return RepositoryResult.error(exception: RepositoryException.unknown);
final chats = entity.items.map((w) => _chatWireMapper.toModel(entity: w)).toList();
final hasMore = (entity.page * entity.pageSize) < entity.total;
final meta = PageMetadata(total: entity.total, nextPage: hasMore ? entity.page + 1 : null);
```

## EntityConverter contract

- `ResponseEntity<T>.fromJson({success, error, data})` resolves `data` to a concrete `T`
  for every registered wire entity (Item/Items, ChatWire/ChatsWire, MessageWire/MessagesWire).
- `ResponseEntity<T>(data: entity).toJson()` serialises `data` symmetrically.
- Unregistered `T` throws `ArgumentError` (explicit "no converter for type $T").

## Invariants (behavior preservation)

- Repos hand the UI the SAME domain models (`ChatModel`/`MessageModel`), same order, same pagination.
- `data == null` or `success:false` → `RepositoryResult.error` (as ItemRepositoryImpl).
- No change to domain models, local Sembast entities/DAO/mappers, seed values, cache-first semantics, UI/BLoC.
