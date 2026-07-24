# Implementation Plan: Image thumbnails + full-screen viewer + real save (F4 + F2)

**Branch**: `020-image-preview-save` · **Spec**: [spec.md](./spec.md) · **Date**: 2026-07-26

## Summary

Capture the picked file's local path on the attachment, then: (F4) render image attachments as an inline thumbnail in the message bubble with a tap → full-screen viewer; keep other types as type-icon chips; (F2) make the file-view Save copy the real file. Graceful fallback everywhere (missing file → chip / mock save). Revises the locked "type-icon chips only" design decision — image-only, by owner request.

## Technical Context

Dart/Flutter 3.44.1, package `nox_app`, Clean Architecture, Freezed, injectable+get_it. `file_selector` (F1, `openFile`/`getSaveLocation`), `flutter_secure_storage`. `Image.file` for local-image render. The picker seam (`FilePickerService`/`PickedFile`), `MessageAttachment`, the Sembast `MessageEntity`/`MessageMapper`, `AppFileChipWidget`, the message bubble (`AppMessageBubbleWidget` takes a `Widget? file`), the thread view (`AppThreadViewWidget` builds the chip), and the file-view (`FileViewPage._save`) all already exist.

**Design decisions (from Clarifications):**
- `localPath` lives on `MessageAttachment` (domain) + persists in Sembast; NOT on the S4 wire attachment (seeded attachments have no file → localPath null → chip). The send echo already forwards the attachment, so a user-sent image's localPath survives.
- Thumbnail = `Image.file(File(localPath))` with an `errorBuilder` falling back to the chip; render decision guarded by `type == image && localPath != null/notEmpty && File(localPath).existsSync()`.
- Full-screen viewer = a new adaptive page (mobile push / desktop lightbox dialog) with `InteractiveViewer` (zoom) + close; `Image.file` with a graceful error placeholder.
- Save = `getSaveLocation` (suggested name = attachment name) → `File(dest).writeAsBytes(await File(localPath).readAsBytes())`; no path/cancel → mock snackbar / no-op.
- macOS: `files.user-selected.read-write` entitlement (upgrade from read-only) for the save write.

## Constitution Check

- **I — Privacy / E2EE**: No network; only local file bytes the user already chose. No new PII. PASS.
- **II — Spec-as-truth**: The spec revises the "type-icon chips only" decision by explicit owner request — a sanctioned spec change, recorded in the spec + the design corpus (this change-set). PASS.
- **III — Architecture blueprint**: Freezed model change + Sembast entity/mapper + presentation; follows the blueprint. `File(...).existsSync()` in a build is a pragmatic local-path check (UI phase). PASS.
- **IV — Design-system fidelity**: The locked `overview.md` "file content previews — type-icon chips only" is REVISED (image previews now in scope) by the design owner. Principle IV is upheld by UPDATING the locked decision + reconciling the per-platform corpus (mobile/desktop screen docs) in the SAME change-set, not by diverging silently. PASS (with the documented owner-authorized revision).
- **V — Language discipline**: Code English, spec/plan Russian. PASS.

**Result: PASS** — presentation + a small model/storage change; the design-decision revision is owner-authorized and reconciled in-change-set.

## Project Structure (files)

```
lib/domain/model/chat/message_attachment.dart     # EDIT — + String? localPath
lib/domain/service/file_picker_service.dart        # EDIT — PickedFile + String? path
lib/data/service/file_picker_service_impl.dart     # EDIT — capture XFile.path
lib/data/entity/chat/message_entity.dart           # EDIT — + attachmentLocalPath
lib/data/mapper/chat/message_mapper.dart           # EDIT — carry localPath both ways
lib/presentation/pages/chat_thread_page/bloc/chat_thread_bloc.dart  # EDIT — draft carries picked.path
lib/presentation/widgets/chat/app_image_attachment_widget.dart      # NEW — inline thumbnail (Image.file + errorBuilder→chip), tap→viewer
lib/presentation/pages/image_viewer_page/image_viewer_page.dart      # NEW — full-screen InteractiveViewer (adaptive)
lib/presentation/widgets/chat/app_thread_view_widget.dart           # EDIT — image attachment → thumbnail, else chip
lib/presentation/pages/file_view_page/file_view_page.dart           # EDIT — _save copies the real file
macos/Runner/*.entitlements                        # EDIT — files.user-selected.read-write
```

Tests mirror under `test/`.

## Phasing

- **Phase 1 — data-model.md + contracts/**: the localPath field flow + the thumbnail/viewer/save contracts.
- **Phase 2 — implement** (tasks.md): foundation (model/picker/entity/mapper/bloc) → thumbnail widget + viewer → thread wiring → save → entitlement → `make generate` → tests → `make gate` + `make golden-verify` + macOS build.

## Risks

- **Stale localPath after restart**: mitigated by `existsSync()` guard + `errorBuilder` → chip; save degrades to mock.
- **Golden churn**: the seed carries a PDF (chip), no image → thread goldens unchanged; the viewer is golden-exempt (image-content-dependent). Verify no delta.
- **`File.existsSync()` in build**: cheap for a local path; acceptable in the UI phase (documented). A real backend would use a cached-URI check instead.
