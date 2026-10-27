---
description: "Task list for 020-image-preview-save"
---

# Tasks: Image thumbnails + full-screen viewer + real save (F4 + F2)

**Input**: design docs in `specs/020-image-preview-save/`
**Tests**: INCLUDED. **Organization**: Foundation → US1 (thumbnail) → US2 (viewer) → US3 (save).

## Path Conventions

Single package `nox_app`: `lib/`, tests deep-mirror under `test/`.

---

## Phase 1: Setup

- [X] T001 Confirm baseline green on `020-image-preview-save`: `make gate` + `make golden-verify`.

---

## Phase 2: Foundation — localPath through the stack (blocks US1/US3)

- [X] T002 Edit `lib/domain/model/chat/message_attachment.dart`: add `String? localPath` (nullable; device-local path, null for seeded/backend).
- [X] T003 Edit `lib/domain/service/file_picker_service.dart`: `PickedFile` gains `String? path`.
- [X] T004 Edit `lib/data/service/file_picker_service_impl.dart`: `pickedFileFrom` + `pickFile` capture `XFile.path` into `PickedFile.path`.
- [X] T005 Edit `lib/data/entity/chat/message_entity.dart`: add `String? attachmentLocalPath` (flattened).
- [X] T006 Edit `lib/data/mapper/chat/message_mapper.dart`: toModel sets `localPath: entity.attachmentLocalPath`; toEntity sets `attachmentLocalPath: model.attachment?.localPath`.
- [X] T007 Edit `lib/presentation/pages/chat_thread_page/bloc/chat_thread_bloc.dart` `_onAttachmentPicked`: the draft `MessageAttachment` carries `localPath: picked.path`.
- [X] T008 Run `make generate` (freezed for MessageAttachment/MessageEntity). Confirm build.
- [X] T009 [P] Test `test/data/mapper/chat/message_mapper_test.dart` (or extend): a message with an attachment localPath round-trips through toEntity→toModel (persist survives). Extend `file_picker_service_impl_test.dart`: `PickedFile.path` == the XFile path.

**Checkpoint**: localPath flows pick→draft→persist and back.

---

## Phase 3: US1 — Inline image thumbnail (Priority: P1)

- [X] T010 [US1] Add `lib/presentation/widgets/chat/app_image_attachment_widget.dart`: `AppImageAttachmentWidget` — `Image.file(File(localPath))` clipped to a rounded, bubble-bounded box (design tokens), `errorBuilder` → `AppFileChipWidget` fallback, `onTap` callback. Uses design tokens only.
- [X] T011 [US1] Edit `lib/presentation/widgets/chat/app_thread_view_widget.dart` (the MESSAGE-BUBBLE attachment build site): if `attachment.type == FileType.image && (attachment.localPath?.isNotEmpty ?? false) && File(localPath).existsSync()` → `AppImageAttachmentWidget` (onTap → viewer, T013); else → `AppFileChipWidget` (unchanged). SCOPE: message bubbles only (the "переписка"); the composer draft-attachment preview stays a chip (pre-send affordance; keeps composer goldens stable).
- [X] T012 [P] [US1] Test `test/presentation/widgets/chat/app_image_attachment_widget_test.dart`: a real temp image file → renders `Image`; a missing path → the `errorBuilder`/guard yields the chip; tap fires `onTap`. (Write a tiny real PNG to a temp file.)

**Checkpoint**: images show as thumbnails, others as chips.

---

## Phase 4: US2 — Full-screen viewer (Priority: P1)

- [X] T013 [US2] Add `lib/presentation/pages/image_viewer_page/image_viewer_page.dart`: `ImageViewerPage(localPath)` + `openImageViewer(context, localPath)` (mobile push / desktop `Dialog` lightbox, mirroring `showFileView`). `InteractiveViewer` (minScale 1, maxScale ~5) around `Image.file`; close (back / X / tap-scrim desktop); missing file → graceful placeholder. Design tokens only.
- [X] T014 [US2] Wire `AppImageAttachmentWidget.onTap` (via the thread view) to `openImageViewer(context, localPath)`.
- [X] T015 [P] [US2] Test `test/presentation/pages/image_viewer_page/image_viewer_page_test.dart`: opening shows `InteractiveViewer`; close pops; a missing file shows the placeholder (no crash). Golden-EXEMPT (image-content-dependent — documented).

**Checkpoint**: tap → full-screen zoomable image → close.

---

## Phase 5: US3 — Real file save (F2, Priority: P2)

- [X] T016 [US3] Edit `lib/presentation/pages/file_view_page/file_view_page.dart` `_save`: if `file.localPath` valid + file exists → `getSaveLocation(suggestedName: file.name)` → write bytes (`File(dest).writeAsBytes(await File(src).readAsBytes())`) + confirm snackbar; cancel → no-op; no path/missing → the existing mock snackbar. Wrap IO in try/catch → error snackbar (never crash). Resolve the `_save` `// TODO(backend)` for the save-copy part.
- [X] T017 [US3] Add the save capability to the picker seam if needed: extend `FilePickerService` with `Future<String?> pickSaveLocation({required String suggestedName})` + impl (`getSaveLocation`), OR call `file_selector` directly in the page with a thin guard. Prefer the seam for testability.
- [X] T018 [P] [US3] Test `test/presentation/pages/file_view_page/file_view_page_test.dart`: with a valid localPath + a faked save-location, Save writes the bytes to the destination; a cancelled location → nothing written; a null localPath → the mock snackbar (no crash).

**Checkpoint**: Save copies the real file.

---

## Phase 6: Native config + Polish

- [X] T019 macOS: add `com.apple.security.files.user-selected.read-write` to BOTH `macos/Runner/DebugProfile.entitlements` + `Release.entitlements` (upgrade from read-only). (read-only stays for the picker; read-write covers the save.)
- [X] T020 Drift-fix (Principle IV, owner-authorized): update `docs/design/spec/overview.md` "file content previews — type-icon chips only" decision → image previews now in scope (owner 2026-07-26); reconcile the per-platform corpus (`nox-mobile-screens`/`nox-desktop-screens` chat-thread screen docs) — image attachment = thumbnail + full-screen. Update the tracker F4/F2.
- [X] T021 Gate: `make gate` + `make golden-verify` (thread goldens UNCHANGED — verify no delta) + `make build-macos-stage` (read-write entitlement links). Walk `quickstart.md`.

---

## Dependencies & Order

- Setup → Foundation (T002–T009) blocks US1/US3. US1 (T010–T012) → US2 (T013–T015, needs the widget's onTap). US3 (T016–T018) independent of US1/US2 after Foundation. Native+Polish last.
- `make generate` once (T008); a second run only if T017 adds an annotation.

## Notes

- The thumbnail/viewer read a LOCAL file; no network. Missing file → graceful chip/placeholder/mock.
- Seeded attachments have no localPath → chip → thread goldens unchanged.
- Local only; never pushed. After all: multi-agent review → fix findings → merge `020-image-preview-save` → `develop` (`--no-ff`).
