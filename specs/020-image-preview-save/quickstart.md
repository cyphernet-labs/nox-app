# Quickstart & Validation: image preview + full-screen + save (F4+F2)

## Automated (the gate)
```bash
make generate        # freezed (MessageAttachment.localPath) + build_runner
make gate            # generate -> format -> analyze -> test (goldens excluded)
make golden-verify   # thread goldens UNCHANGED (seed = PDF chip, no image)
make build-macos-stage  # verifies the files.user-selected.read-write entitlement
```
Targeted:
```bash
make test FILE=test/data/mapper/chat/message_mapper_test.dart                 # localPath persists
make test FILE=test/data/service/file_picker_service_impl_test.dart           # PickedFile.path captured
make test FILE=test/presentation/widgets/chat/app_image_attachment_widget_test.dart  # thumbnail vs chip fallback + tap
make test FILE=test/presentation/pages/image_viewer_page/image_viewer_page_test.dart # viewer open/close + missing-file
make test FILE=test/presentation/pages/file_view_page/file_view_page_test.dart # save copies / cancel / mock fallback
```

## Manual
- Attach an image in a chat → the bubble shows the picture (not an icon); tap → full-screen with zoom; back returns.
- Attach a pdf/zip → type-icon chip as before.
- File view → Save → pick a folder → the real file is copied there.

## Success-criteria mapping
| Criterion | Validated by |
|-----------|--------------|
| SC-001 (thumbnail vs chip, 3 branches) | app_image_attachment_widget_test |
| SC-002 (tap → viewer → close) | image_viewer_page_test + widget tap test |
| SC-003 (save copies / cancel / mock) | file_view_page_test |
| SC-004 (localPath survives restart) | message_mapper_test (+ repo round-trip) |
| SC-005 (no regressions; goldens unchanged; macOS builds) | make gate + golden-verify + macOS build |
| SC-006 (graceful on missing file) | widget/viewer/save missing-file tests |

## Rollback
Reverting the branch restores type-icon-chips-only + the mock save. Persisted localPath is ignored by the old render path.
