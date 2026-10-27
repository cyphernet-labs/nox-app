# Data Model: Real File Attachments

No new persisted schema. One new in-memory value (`PickedFile`), one enum extension (`FileType.fromExtension`), and a derivation rule for chat files. Attachments continue to live inside `MessageModel`.

## Entities

### PickedFile (in-memory) — NEW

The transient result of the native picker, before it becomes a `MessageAttachment`.

| Field | Type | Notes |
|-------|------|-------|
| `name` | `String` | The chosen file's real display name (with extension). |
| `sizeBytes` | `int` | The chosen file's real size in bytes. |
| `extension` | `String?` | The chosen file's extension (no dot), or null. Drives `FileType.fromExtension`. |

Representation: a record `({String name, int sizeBytes, String? extension})` returned by `FilePickerService.pickFile()` (nullable — `null` = cancelled / unsupported). No persistence.

### MessageAttachment (existing) — unchanged shape

`{ String id, FileType type, String name, int sizeBytes }`. Feature 017 changes how it is POPULATED (from a real `PickedFile`, not the `photo.jpg` stub) and how the files view is SOURCED (derived from persisted messages), not the shape.

### FileType (existing enum) — extended with a mapper

`enum FileType { image, video, audio, pdf, doc, sheet, text, archive, other }`. Add a pure static `FileType.fromExtension(String? ext)` (case-insensitive; unknown/null → `other`) per the R3 table.

## Derivation rule — chat shared files

```
chatFiles(chatId):
    seedChatIfEmpty(chatId)                       # ensure the thread is populated
    messages = messageDao.getByChatSorted(chatId) # ascending by sentAt
    return [ m.attachment for m in reversed(messages) if m.attachment != null ]   # newest-first
```

Consumed by `ChatRepositoryImpl.getChatFiles` (delegates to `MessageRepository.chatFiles`). The result is the `List<MessageAttachment>` the 5.4 view renders — exactly the chat's real attachments, newest-first, nothing fabricated.

## Draft-attachment mapping (F1)

```
_onAttachmentPicked:
    picked = await filePickerService.pickFile()
    if picked == null: return                       # cancel / unsupported → composer unchanged
    draftAttachment = MessageAttachment(
        id: uuid.v4(),
        name: picked.name,
        sizeBytes: picked.sizeBytes,
        type: FileType.fromExtension(picked.extension),
    )
```

## Removed (016 files seam)

- `ChatFilesRemoteDataSource` (interface) + `MockChatFilesRemoteDataSource` (impl) — removed.
- `GetChatFilesApi` (the fabricated 8-file generator) + its unit test — removed.
- `ChatRepositoryImpl` drops the `ChatFilesRemoteDataSource` constructor dependency; `getChatFiles` delegates to `MessageRepository.chatFiles`.

Untouched: the chat-list (`ChatRemoteDataSource`) and message (`MessageRemoteDataSource`) seams; `RepositoryResult`/`PageMetadata`; the file chip/glyph/size formatter; the mock message seed (keeps its one attachment).
