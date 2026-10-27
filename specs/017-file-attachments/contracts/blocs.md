# Contract: BLoC changes

No new events/states — existing handlers gain real behaviour.

## ChatThreadBloc (F1)

**`_onAttachmentPicked`** — was a sync stub emitting a fixed `photo.jpg`; becomes async and drives the real picker:

```dart
Future<void> _onAttachmentPicked(AttachmentPicked event, Emitter<ChatThreadState> emit) async {
  final current = state;
  if (current is! Initialized) return;
  final picked = await _filePickerService.pickFile();
  if (picked == null) return; // cancelled / unsupported → composer unchanged (FR-004)
  emit(current.copyWith(draftAttachment: MessageAttachment(
    id: _uuid.v4(),
    name: picked.name,
    sizeBytes: picked.sizeBytes,
    type: FileType.fromExtension(picked.extension),
  )));
}
```

- New dependency: `FilePickerService` (from DI). Uses the existing `_localCounter`/uuid convention for the id.
- `AttachmentRemoved` and the send flow (the draft attachment rides on `messageSent`) are UNCHANGED — a picked real attachment sends exactly as the stub did.
- Acceptance: real name/size/type in the draft (US1-1/2), cancel leaves it unchanged (US1-3), send carries it (US1-5).

## ChatCardBloc (E3 + R5)

- **Source (E3)**: `_onInitialize` still calls `_chatRepository.getChatFiles(chatId)` — now returns the derived real attachments (newest-first). No bloc change beyond behaviour.
- **Reactivity (R5)**: subscribe to `messageRepository.watchMessages(chatId)` (skip(1) + debounce) → re-add `initialize` to re-derive; cancel in `close()`. New dependency: `MessageRepository` (for the watch signal). The `empty`/`offline`/`fatal` scenario overrides are preserved.
- Acceptance: view lists the chat's real files (US2), a newly sent file appears without reload (US3).

## Removed

`GetChatFilesApi`, `ChatFilesRemoteDataSource`, `MockChatFilesRemoteDataSource` deleted; `ChatRepositoryImpl` drops that dependency (delegates to `MessageRepository.chatFiles`). DI regenerated.
