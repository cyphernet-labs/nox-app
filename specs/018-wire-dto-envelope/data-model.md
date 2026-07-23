# Data Model: Uniform wire-DTO envelope for chat & message (S4)

Wire DTOs are freezed + json_serializable, **basic types only** (mirror `ItemEntity`). All coercion lives in the wire mapper. These are the NETWORK-boundary shape — distinct from the LOCAL Sembast entities (`ChatEntity`/`MessageEntity`), which stay the storage shape.

## Wire entities (`lib/data/entity/chat/wire/`)

| Entity | Fields (JSON key) | Notes |
|--------|-------------------|-------|
| `ChatWireEntity` | `id`, `name`, `last_message_preview`, `last_message_at` (ISO String), `unread_count` (int) | mirrors `ChatModel` |
| `ChatsWireEntity` | `items: List<ChatWireEntity>`, `page`, `page_size`, `total` | page wrapper (mirrors `ItemsEntity`) |
| `MessageAttachmentWireEntity` | `id`, `type` (String enum), `name`, `size_bytes` (int) | nested; nullable on the message |
| `MessageWireEntity` | `id`, `chat_id`, `author_id`, `author_label`, `text` (String?), `sent_at` (ISO String), `status` (String enum), `is_system` (bool), `attachment` (`MessageAttachmentWireEntity?`) | mirrors `MessageModel` |
| `MessagesWireEntity` | `items: List<MessageWireEntity>`, `page`, `page_size`, `total` | page wrapper |

## Mappers (`lib/data/mapper/chat/`)

| Mapper | Direction | Coercion |
|--------|-----------|----------|
| `ChatWireMapper` | `ChatWireEntity → ChatModel` (`toModel`) · `ChatModel → ChatWireEntity` (`toWire`) | ISO String ↔ DateTime (UTC on wire, local in model — mirror `ChatMapper`) |
| `MessageWireMapper` | `MessageWireEntity ↔ MessageModel` | enum `name` ↔ String; ISO ↔ DateTime; nested attachment (`FileType.name`/`values.byName`), null-safe |

Model→wire (`toWire`) is used by the generator; wire→model (`toModel`) by the repo. Round-trip (`toModel(toWire(m))`) is loss-free for all fields.

## `EntityConverter` registry (`lib/data/entity/base/entity_converter.dart`)

Registered branches (both `fromJson` and `toJson`), by reachability via `ResponseEntity<T>`:

| Registered `T` | fromJson | toJson |
|----------------|----------|--------|
| `ItemEntity`, `ItemsEntity` | `T.fromJson(map)` | `object.toJson()` |
| `ChatWireEntity`, `ChatsWireEntity` | ″ | ″ |
| `MessageWireEntity`, `MessagesWireEntity` | ″ | ″ |
| any other `T` | throws `ArgumentError` | throws `ArgumentError` |

## Envelope flow (per list boundary)

```
GetChatsApi.execute(config)                 # build model seed (unchanged) → map model→wire →
  → ResponseEntity<ChatsWireEntity>(success:true, data: ChatsWireEntity(items, page, page_size, total))
MockChatRemoteDataSource.getChats(config)   # forward (thin)
ChatRepositoryImpl._seedIfEmpty/getChats    # unwrap: data==null → RepositoryResult.error;
                                            # else map wire→model + PageMetadata(total, nextPage=page*pageSize<total?page+1:null)
  → identical (List<ChatModel>, PageMetadata) as before   # SC-001
```

Message boundary is identical with `MessagesWireEntity`/`MessageModel` (nested attachment). `sendMessage` unchanged.
