# Quickstart & Validation: Real File Attachments

## Prerequisites

- `make deps` (adds `file_picker`), `make generate` (DI for the new service + repo/bloc constructor changes).
- Desktop run to try the real picker: `fvm flutter run -d macos --dart-define-from-file=config/stage.json`.

## Automated validation (the gate)

```bash
make gate            # generate → format → analyze → test (goldens excluded)
make golden-verify   # the 5.4 files-view baseline regenerates to the derived attachment; no picker golden
```

Targeted:

```bash
make test FILE=test/domain/model/file/file_type_test.dart                 # extension → FileType
make test FILE=test/data/service/mock_file_picker_service_test.dart       # seam (fake) — pick/cancel
make test FILE=test/presentation/pages/chat_thread_page/bloc/chat_thread_bloc_test.dart  # picker → draft
make test FILE=test/data/repository/chat/message_repository_impl_test.dart # chatFiles derivation
make test FILE=test/presentation/pages/chat_card_page/bloc/chat_card_bloc_test.dart      # reactive files
```

## Manual validation

### US1 — attach a real file
1. Open a chat, tap the composer's attach (paperclip).
2. **Expect**: the OS file picker opens. Choose `report.pdf`. The composer shows a chip: `report.pdf`, its real size, PDF glyph.
3. Choose files of other types (image/zip/mp3/xlsx/…): the glyph matches. Choose an extensionless/unknown file: the generic glyph.
4. Tap attach, then Cancel: the composer is unchanged.
5. Send a message with the attachment: the sent bubble carries it.

### US2 — files view shows real files
1. In a chat with attachments, open the chat card → shared files.
2. **Expect**: exactly the files sent in that chat, newest-first; nothing else.
3. Open a brand-new chat's files view: empty.

### US3 — files view stays current
1. With the files view reflecting a chat, attach+send a new file, reopen/return to the files view.
2. **Expect**: the new file is there, no manual reload.

## Success-criteria mapping

| Criterion | Validated by |
|-----------|--------------|
| SC-001 (real picker, no photo.jpg) | US1 · `chat_thread_bloc_test` |
| SC-002 (name/size/type match) | US1 step 2-3 · `file_type_test` + service test |
| SC-003 (cancel = no change) | US1 step 4 · `chat_thread_bloc_test` |
| SC-004 (files = real, per-chat) | US2 · `message_repository_impl_test` chatFiles |
| SC-005 (new file live) | US3 · `chat_card_bloc_test` reactive |
| SC-006 (builds + picker wired, fallback) | macOS build + the null-on-failure seam contract |
| SC-007 (0 regressions) | full `make gate` + `make golden-verify` |

## The macOS build check (native config)

```bash
make build-macos-stage   # verifies the file-access entitlement compiles/links; run the app + tap attach
```

iOS/Android/Windows/Linux use the plugin-standard config — flagged for a build check when CI resumes (compile-check.yml).

## Rollback / safety

- No schema, no bytes stored. Reverting the branch restores the stub picker + the fabricated files list.
- The picker seam returns `null` on any failure, so a missing native config degrades to "attach does nothing," never a crash.
