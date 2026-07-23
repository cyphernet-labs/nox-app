# Implementation Plan: Real File Attachments

**Branch**: `017-file-attachments` | **Date**: 2026-07-25 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/017-file-attachments/spec.md`

## Summary

Three connected client-side outcomes, no backend: **(F1)** the composer's attach action opens the real native file picker (`file_selector`, blueprint-planned) behind a mockable domain `FilePickerService` seam; the chosen file's real name/size + an extension-derived `FileType` populate the draft attachment (replacing the fixed `photo.jpg` stub); no-bytes-read (`XFile.length()`) so no bytes are read. **(E3)** the 5.4 shared-files view is derived from the chat's PERSISTED message attachments (newest-first) via `MessageRepository.chatFiles`, retiring the fabricated `GetChatFilesApi` and the now-vestigial 016 `ChatFilesRemoteDataSource` (chat files are a local cache derivation, not a remote fetch). **(R5)** `ChatCardBloc` subscribes to `watchMessages` (the feature-014 change-signal) so a newly attached-and-sent file appears in the files view without a reload. Native config: the macOS user-selected read-only file-access entitlement; other targets work with standard config.

## Technical Context

**Language/Version**: Dart `>=3.12 <4.0`, Flutter `3.44.1` (FVM-pinned)

**Primary Dependencies**: **NEW `file_selector`** (blueprint-planned; the only new package); flutter_bloc + freezed (BLoC), injectable + get_it (DI), rxdart (stream ops), Sembast (message cache), uuid.

**Storage**: unchanged — attachments live inside `MessageEntity`/`MessageModel` in the Sembast message cache; the files view derives from it. No new persistence, no file bytes stored.

**Testing**: `flutter_test` + `bloc_test` against the test-env DI; the picker is mocked via the `FilePickerService` interface (no real OS dialog). `mockito` where a path must be forced. Goldens: the 5.4 files-view baseline (if any) regenerates to the real derived attachment; no picker golden (OS sheet).

**Target Platform**: iOS, Android, macOS, Windows, Linux. `file_selector` supports all five; macOS (sandbox) needs `com.apple.security.files.user-selected.read-only` in both entitlement files. iOS document picking needs no usage string; Android/Windows/Linux work with the plugin default.

**Project Type**: single Flutter package `nox_app`, Clean Architecture layers-as-folders.

**Performance Goals**: attach opens the OS picker immediately; no-bytes-read (`XFile.length()`) avoids loading file bytes so large files never block the UI; a new file reflects in the files view within ~1s (SC-005).

**Constraints**: no backend/upload/download; no file bytes read; no raw `print`; design tokens only; one `build_runner` pass; line length 140.

**Scale/Scope**: ~1 new package, 1 domain service (+mock/real impl), 1 extension→type util, edits to 3 blocs (thread picker, card reactive) + 2 repositories (message chatFiles, chat delegate), removal of the 016 ChatFiles seam (3 files + 1 test), macOS entitlements.

## Constitution Check

*GATE: evaluated against `.specify/memory/constitution.md` v1.1.0 (principles I–V).*

- **I. Privacy & E2EE** — PASS. Metadata-only: no-bytes-read (`XFile.length()`) means no file bytes are read, uploaded, downloaded, or stored. No content leaves the device (there is no transfer). The file's own name is user-chosen local data, not PII collected by the app; it is not logged with analytics. No crypto/identity touched.
- **II. Spec & design corpus = source of truth** — PASS. Spec-driven. In-same-change-set drift fixes: the 016 tracker/data-model/blueprint notes that describe `ChatFilesRemoteDataSource` are updated to reflect its removal (chat files are now a local derivation); the `_onAttachmentPicked` and `getChatFiles` `TODO`s are resolved. Locked out-of-scope (upload/download, preview, multi-select, camera) stays out.
- **III. Architecture blueprint mandatory** — PASS. `file_selector` is a **blueprint-planned** dependency (pubspec comment + the `_onAttachmentPicked` TODO name it). Freezed BLoCs, `RepositoryResult<T>`, injectable + get_it, a **domain service seam** (`FilePickerService`) over the plugin (blocs stay testable/mockable — the QR feature's `CameraPermissionService` precedent), design tokens, no raw `print`. Platform-specific native config (Principle III): the picker's per-platform setup is added; the defensive fallback is documented (QR-fallback precedent). Locally-unbuildable targets (iOS/Android/Windows/Linux) are flagged for a build check when CI resumes; macOS is verified locally.
- **IV. Design-system fidelity** — PASS. No new tokens/visuals: the file chip/glyph, size formatter, and type icons/colors already exist and are reused; only the *values* (real name/size/type) change.
- **V. Language discipline** — PASS. Code/identifiers/commits English; this doc + chat Russian.

**Result: PASS — no violations, Complexity Tracking empty.**

## Project Structure

### Documentation (this feature)

```text
specs/017-file-attachments/
├── plan.md · research.md · data-model.md · quickstart.md
├── contracts/{file-picker-service.md, files-derivation.md, blocs.md}
├── checklists/requirements.md
└── tasks.md   (/speckit-tasks)
```

### Source Code (repository root)

```text
lib/
├── domain/
│   ├── service/file_picker_service.dart        # NEW abstract FilePickerService + PickedFile
│   └── model/file/file_type.dart               # EXTEND: FileType.fromExtension(String?)
├── data/
│   ├── service/file_picker_service_impl.dart    # NEW real impl wrapping file_picker (all envs)
│   ├── repository/chat/message_repository_impl.dart  # NEW chatFiles(chatId) + watch signal
│   └── repository/chat/chat_repository_impl.dart      # getChatFiles → delegate; drop ChatFilesRemote dep
├── data/remote/datasource/                     # REMOVE chat_files_remote_data_source.dart + mock/
├── data/remote/api/chat/get_chat_files_api.dart  # REMOVE (fabricated list retired)
├── domain/repository/chat/message_repository.dart # EXTEND: chatFiles(...) [+ watchChatFiles or reuse watchMessages]
└── presentation/pages/
    ├── chat_thread_page/bloc/chat_thread_bloc.dart   # _onAttachmentPicked → real picker (async)
    └── chat_card_page/bloc/chat_card_bloc.dart       # reactive files (watch → re-derive)

macos/Runner/{DebugProfile,Release}.entitlements     # ADD files.user-selected.read-only

test/  (deep-mirror) — service unit test, extension-map unit test, message/chat repo chatFiles tests,
   thread-bloc picker test (mocked service), card-bloc reactive test; remove get_chat_files_api_test.
```

**Structure Decision**: A domain `FilePickerService` seam (mirroring the QR `CameraPermissionService`) keeps `ChatThreadBloc` testable without an OS dialog and makes the plugin swappable. Chat files become a **local derivation** from the message cache (`MessageRepository.chatFiles`), so the 016 `ChatFilesRemoteDataSource`/`GetChatFilesApi` (which modeled files as a remote fetch of a fabricated list) is removed — the seam is retained for chat-list and messages, but chat *files* are not a network resource.

## Key design decisions (see research.md)

1. **FilePickerService seam.** `abstract FilePickerService { Future<PickedFile?> pickFile(); }`, `PickedFile = ({String name, int sizeBytes, String? extension})`. Real impl calls `openFile()` (file_selector), maps the `XFile`, returns `null` on cancel OR on any plugin failure (defensive fallback, non-crashing). Registered for all envs; tests inject a fake.
2. **Extension → FileType** via a pure `FileType.fromExtension(String? ext)` (jpg/png/gif/webp→image, mp4/mov/mkv→video, mp3/m4a/wav/aac→audio, pdf→pdf, doc/docx→doc, xls/xlsx/csv→sheet, txt/md/rtf→text, zip/rar/7z/tar/gz→archive, else→other).
3. **Files derived from the message cache.** `MessageRepository.chatFiles(chatId)` = seed-if-empty → `getByChatSorted` → collect non-null attachments **newest-first**. `ChatRepositoryImpl.getChatFiles` delegates to it. `ChatFilesRemoteDataSource`/`GetChatFilesApi` removed.
4. **Reactive files (R5).** `ChatCardBloc` subscribes to `messageRepository.watchMessages(chatId).skip(1).debounceTime(100ms)` → re-adds a refresh event that re-derives via `getChatFiles`. Same change-signal pattern as feature 014; cancelled in `close()`.
5. **No new goldens for the picker** (OS sheet). The 5.4 files-view golden (if present) regenerates to the derived attachment (a behavioural source change, not a layout change).

## Complexity Tracking

No constitution violations — section intentionally empty.
