# Research: Real File Attachments

Phase 0 decisions, grounded in the current `lib/` code + the target platforms.

## R1 — Picker plugin + how the bloc stays testable

**Decision**: Use **`file_selector`** (official flutter.dev plugin) behind a domain **`FilePickerService`** interface. `ChatThreadBloc` depends on the interface, never the plugin, so it is mockable in `bloc_test` without an OS dialog — exactly the pattern feature-010 used for `CameraPermissionService`.

**Rationale**: `file_picker` was the blueprint-named choice (pubspec comment + the `_onAttachmentPicked` TODO), but every modern `file_picker` (5.x–8.x) pins `win32 ^5.x`, which conflicts with the project's `package_info_plus ^10.1.0` (needs `win32 ^6.0.1`) — version solving fails (only the ancient, unmaintained `file_picker 3.0.4` resolves). `file_selector` (flutter.dev, all five targets, `XFile`-based) resolves cleanly and exposes name/size/extension. Wrapping either behind `FilePickerService` means the plugin is an implementation detail — the bloc is unaffected by the swap.

**Alternatives considered**:
- *`file_picker`* — the plan's first choice, but its `win32` constraint is incompatible with `package_info_plus ^10.1.0`. Rejected on the version conflict.
- *`image_picker`* — photos/videos only; NOX attaches ANY file. Rejected.
- *Call the plugin inline in the bloc* — untestable; rejected.

## R2 — Metadata only (no bytes read)

**Decision**: `openFile()` (file_selector; no type groups → any file) → capture `XFile.name`, `await XFile.length()` (size), and the extension from the name; never call `readAsBytes()`/read the content.

**Rationale**: The UI-first phase transfers nothing; `MessageAttachment` holds only name/size/type. `XFile.length()` stats the size without loading the file, so large files never block the UI. Constitution I: no bytes read / leave the device.

## R3 — Extension → FileType mapping

**Decision**: A pure `FileType.fromExtension(String? ext)` on the existing enum. Case-insensitive; unknown/empty → `other`.

| Class | Extensions |
|-------|-----------|
| image | jpg, jpeg, png, gif, webp, heic, bmp, svg |
| video | mp4, mov, mkv, avi, webm |
| audio | mp3, m4a, wav, aac, flac, ogg |
| pdf | pdf |
| doc | doc, docx, odt, pages |
| sheet | xls, xlsx, csv, numbers, ods |
| text | txt, md, rtf, log |
| archive | zip, rar, 7z, tar, gz |
| other | everything else / none |

**Rationale**: Deterministic, testable (SC-002), reuses the existing `FileType`. The list is a reasonable default; the mapper is the single source so it is easy to extend.

## R4 — Chat files: derive locally, remove the remote seam

**Decision**: `getChatFiles` derives from the **persisted message attachments** (local Sembast cache), newest-first, via `MessageRepository.chatFiles(chatId)`. The 016 `ChatFilesRemoteDataSource` + `MockChatFilesRemoteDataSource` + `GetChatFilesApi` (a fabricated fixed list modeled as a remote fetch) are **removed**.

**Rationale**: In NOX's open shared space the client holds all messages, so the files view is a client-side projection of the message history — not a network resource. The 016 seam over-modeled it (understandable — it wrapped the pre-existing fabricated `GetChatFilesApi`). Feature 017 corrects that: files are local. `ChatRepositoryImpl` already injects `MessageRepository` (feature D5), so the delegation adds no new dependency; it drops the `ChatFilesRemoteDataSource` one.

**Alternatives considered**:
- *Keep the seam, make the mock derive from `MessageDao`* — a "remote" data source reading the local cache is an inversion/smell; and it leaves a dead abstraction. Rejected.
- *Defer E3 until real varied attachments exist* — was the pre-017 stance, but F1 now provides real attachments in the SAME feature, so deriving is correct here. The seeded chat keeps its one attachment; users add more via F1. The old 8-file fabricated demo is intentionally retired (it implied files never sent).

**Seeding**: `MessageRepository.chatFiles` reuses the private `_seedChatIfEmpty` so the view is correct even if the card is opened before the thread; in the normal flow (card reached from the thread) it is already seeded and the seed is a no-op.

## R5 — Reactive files view (R5)

**Decision**: `ChatCardBloc` subscribes to `messageRepository.watchMessages(chatId).skip(1).debounceTime(100ms)` and, on a tick, re-derives the files (re-calls `getChatFiles`) — the feature-014 "watch-as-change-signal" pattern. Cancelled in `close()`. The scenario overrides (empty/offline/fatal) are unchanged.

**Rationale**: Reuses the proven reactive pattern; a sent attachment writes to the message store → `watchMessages` fires → files re-derived. No new stream mechanism.

## R6 — Native configuration + fallback

**Decision**:
- **macOS**: add `com.apple.security.files.user-selected.read-only` to `DebugProfile.entitlements` + `Release.entitlements` (sandbox requires it to read a user-picked file's metadata).
- **iOS**: `file_selector` uses `UIDocumentPickerViewController` for arbitrary files — no `Info.plist` usage string needed (that is only for the photo library / camera).
- **Android / Windows / Linux**: work with the plugin default (no extra config).
- **Fallback**: the `FilePickerService` real impl returns `null` on any plugin exception, so the attach action never crashes; the attach affordance stays visible on all targets (the picker is supported everywhere — this is NOT the QR case where Windows/Linux lack a camera).

**Rationale**: `file_selector` supports all five targets; only macOS's sandbox needs the read-only file entitlement. The `null`-on-failure contract is the defensive safeguard FR-009 asks for.

**Verification gap**: macOS is verified locally (`mise run build:macos:stage` / `make build-macos-stage`). iOS/Android/Windows/Linux builds can't be run locally (CI paused); the config is the plugin-standard set, flagged for a build check when CI resumes.

## R7 — Testing & goldens

**Decision**: Unit test `FileType.fromExtension` (all classes + unknown); unit/bloc test the `FilePickerService` seam via a fake (pick → draft attachment; cancel → unchanged); repo tests for `chatFiles` (derived, newest-first, per-chat, empty); a `ChatCardBloc` reactive test (a new attachment ticks the view). Remove `get_chat_files_api_test`. Regenerate the 5.4 files-view golden if one exists (derived attachment instead of the fabricated eight). No picker golden.
