# Contract: chat files derivation + reactivity (E3 + R5)

## MessageRepository extension (E3)

```dart
// lib/domain/repository/chat/message_repository.dart
/// The chat's shared files — every attachment across its persisted messages,
/// newest-first. Derived from the local message cache (not a remote fetch).
Future<List<MessageAttachment>> chatFiles({required String chatId});
```

Impl (`MessageRepositoryImpl.chatFiles`): `await _seedChatIfEmpty(chatId)` → `getByChatSorted(chatId)` (ascending) → collect `m.attachment` where non-null, **reversed** (newest-first).

## ChatRepository (E3) — delegate, drop the remote seam

`ChatRepository.getChatFiles({chatId})` signature is UNCHANGED (still `Future<RepositoryResult<List<MessageAttachment>>>`). The impl changes:

```dart
@override
Future<RepositoryResult<List<MessageAttachment>>> getChatFiles({required String chatId}) {
  return execute(() async {
    final files = await _messageRepository.chatFiles(chatId: chatId);
    return RepositoryResult.success(data: files);
  });
}
```

`ChatRepositoryImpl` drops its `ChatFilesRemoteDataSource` constructor dependency. `ChatFilesRemoteDataSource`, `MockChatFilesRemoteDataSource`, and `GetChatFilesApi` are deleted.

## ChatCardBloc reactivity (R5)

```dart
// on Initialize: after the first derive, subscribe to the change-signal.
_filesSub ??= messageRepository
    .watchMessages(_chatId)
    .skip(1)                                  // the initial snapshot is the reset load
    .debounceTime(const Duration(milliseconds: 100))
    .listen((_) => add(ChatCardEvent.initialize(_chatId))); // re-derive (invisible refresh)
// close(): _filesSub?.cancel();
```

- On a new attachment sent to the chat, the message store changes → `watchMessages` ticks → the card re-derives the files (a new file appears, newest-first) without a manual reload (FR-008 / SC-005).
- The `empty`/`offline`/`fatal` debug scenarios still override the derived result (unchanged).
- Re-adding `initialize` keeps the derive path single-sourced; the debounce coalesces bursts.

## Behavioural guarantees

| Guarantee | Detail |
|-----------|--------|
| Real files only | The view lists exactly the chat's message attachments — 0 fabricated, 0 missing (FR-006, SC-004). |
| Newest-first | Most recently shared file at the top (clarified). |
| Per-chat | Each chat's view shows only its own files (different chatId → different messages). |
| Empty | A chat with no attachments → empty files list (FR-007). |
| Live | A sent attachment appears without reload (FR-008). |
| Contracts frozen | `RepositoryResult`/`PageMetadata`/error mapping unchanged; only the data SOURCE for files changes. |
