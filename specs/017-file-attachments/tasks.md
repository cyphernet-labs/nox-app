---
description: "Task list for 017-file-attachments"
---

# Tasks: Real File Attachments

**Input**: Design documents from `specs/017-file-attachments/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: INCLUDED (blueprint mandate + plan R7). The picker is mocked via the `FilePickerService` seam (no OS dialog). The 5.4 files-view golden regenerates to the derived attachment; no picker golden.

**Organization**: grouped by user story — US1 (F1 picker), US2 (E3 derived files), US3 (R5 reactive).

## Format: `[ID] [P?] [Story] Description`

## Path Conventions

Single Flutter package `nox_app`: `lib/`, tests deep-mirror under `test/`.

---

## Phase 1: Setup

- [X] T001 Confirm the pre-work baseline green on `017-file-attachments`: `make gate` (620) + `make golden-verify` (152).
- [X] T002 Add the picker dependency `fvm flutter pub add file_selector`. NOTE: the plan named `file_picker`, but its `win32` requirement conflicts with the project's `package_info_plus ^10.1.0` (needs win32 ^6.0.1) — `file_selector` (official flutter.dev, all five targets) resolves cleanly and is used instead. Confirm `make deps` + `flutter analyze` clean.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the extension→type mapper + the picker seam. Block US1.

- [X] T003 [P] Extend `lib/domain/model/file/file_type.dart`: add `static FileType fromExtension(String? ext)` (case-insensitive; unknown/null → `other`) per the research R3 table (image/video/audio/pdf/doc/sheet/text/archive).
- [X] T004 [P] Unit test `test/domain/model/file/file_type_test.dart`: each class maps (e.g. `jpg→image`, `mp4→video`, `mp3→audio`, `pdf→pdf`, `docx→doc`, `xlsx→sheet`, `md→text`, `zip→archive`); unknown (`xyz`) and null/empty → `other`; case-insensitive (`PDF→pdf`). (depends on T003)
- [X] T005 Add `lib/domain/service/file_picker_service.dart`: `typedef PickedFile = ({String name, int sizeBytes, String? extension});` + `abstract class FilePickerService { Future<PickedFile?> pickFile(); }` (contract in `contracts/file-picker-service.md`).

**Checkpoint**: mapper + seam ready.

---

## Phase 3: User Story 1 - Attach a real file (Priority: P1) 🎯 MVP

**Goal**: the composer's attach opens the real picker; the chosen file's real name/size/type populate the draft (replacing the photo.jpg stub); cancel leaves it unchanged.

**Independent Test**: mock the service to return a known file → draft matches; return null → composer unchanged.

### Implementation

- [X] T006 [US1] Add `lib/data/service/file_picker_service_impl.dart`: `FilePickerServiceImpl implements FilePickerService` `@LazySingleton(as: FilePickerService, env:[dev,prod,test])`; `pickFile()` = `openFile()` (file_selector, any file) → map the `XFile` to `PickedFile` (`name`, `await length()` for size, extension from the name), `null` on cancel, `try/catch → null` on any plugin failure (defensive fallback, never throws). See `contracts/file-picker-service.md`.
- [X] T007 [US1] Add the macOS entitlement `com.apple.security.files.user-selected.read-only` (`<true/>`) to `macos/Runner/DebugProfile.entitlements` AND `macos/Runner/Release.entitlements`.
- [X] T008 [US1] In `lib/presentation/pages/chat_thread_page/bloc/chat_thread_bloc.dart`: inject `FilePickerService`; make `_onAttachmentPicked` async → `pickFile()`; on null return (composer unchanged); else `emit(copyWith(draftAttachment: MessageAttachment(id: uuid, name, sizeBytes, type: FileType.fromExtension(ext))))`. Remove the `photo.jpg` stub + its `// TODO(backend)`.
- [X] T009 [US1] Run `make generate` — DI for the new `FilePickerService` binding + the `ChatThreadBloc` field (getIt resolution). Confirm the config wires it.
- [X] T010 [P] [US1] Test `test/data/service/file_picker_service_impl_test.dart`: the mapping from a real `XFile` (name → PickedFile name/extension; length → sizeBytes) is exercised (via file_selector's test hook / a fake `XFile`, or a focused mapping helper); the cancel path (openFile → null → null) and the failure path (throws → null fallback) are covered. If file_selector's platform is not easily fakeable, extract the XFile→PickedFile mapping into a testable pure helper and unit-test that + the null/error guards.
- [X] T011 [P] [US1] Extend `test/presentation/pages/chat_thread_page/bloc/chat_thread_bloc_test.dart`: register a fake `FilePickerService` (getIt); `attachmentPicked` with a known picked file → `draftAttachment` has that real name/size/type (`FileType.fromExtension`); a null-returning fake → `draftAttachment` unchanged. Update the old stub-`photo.jpg` assertion.

**Checkpoint**: US1 functional — real picker → real draft.

---

## Phase 4: User Story 2 - Files view shows the real files (Priority: P1)

**Goal**: the 5.4 files view derives from the chat's persisted attachments (newest-first); the fabricated remote source is removed.

**Independent Test**: a chat with attachments → the view lists exactly them; empty chat → empty; per-chat isolation.

### Implementation

- [X] T012 [US2] `lib/domain/repository/chat/message_repository.dart` + impl: add `Future<List<MessageAttachment>> chatFiles({required String chatId})`; impl `_seedChatIfEmpty` → `getByChatSorted` → collect non-null `attachment`, **reversed (newest-first)**.
- [X] T013 [US2] `lib/data/repository/chat/chat_repository_impl.dart`: `getChatFiles` delegates to `_messageRepository.chatFiles(chatId)` (wrapped in `execute`); drop the `_chatFilesRemote` field + constructor param + import.
- [X] T014 [US2] Delete `lib/data/remote/datasource/chat_files_remote_data_source.dart`, `lib/data/remote/datasource/mock/mock_chat_files_remote_data_source.dart`, `lib/data/remote/api/chat/get_chat_files_api.dart`, and `test/data/remote/api/chat/get_chat_files_api_test.dart`.
- [X] T015 [US2] Run `make generate` — DI regenerates without the removed ChatFiles bindings and with `ChatRepositoryImpl`'s new constructor (drops one dep). (depends on T012–T014)
- [X] T016 [P] [US2] Extend `test/data/repository/chat/message_repository_impl_test.dart`: `chatFiles` returns the seeded chat's attachment(s) newest-first; a chat with an added attachment lists it first; a chat whose messages have no attachments → empty; per-chat isolation.
- [X] T017 [P] [US2] Verify `test/presentation/pages/chat_card_page/bloc/chat_card_bloc_test.dart` still passes (files isNotEmpty holds — chat_0's seed has one attachment); adjust only if it asserted fabricated-specific files.
- [X] T018 [US2] Update the 5.4 files-view golden. Two changes: (a) it renders `chat_0`, whose seeded thread has one attachment (`design-spec.pdf`), so the derived view is NON-empty — regenerate to that single real file (was the fabricated eight); (b) AFTER T019 makes `ChatCardBloc` reactive, the current `goldenTest`/`goldenTestDesktop` (pumpAndSettle) may hang on the watch subscription — convert `chat_card_page_golden_test.dart` to the BESPOKE bounded-pump harness (frozen clock + fonts + pinned surface + bounded pumps), mirroring `chat_thread_page_golden_test.dart`. Then `make golden-update` + verify determinism twice + eyeball. (ordering: do this after T019.)

**Checkpoint**: US2 — real, per-chat files view.

---

## Phase 5: User Story 3 - Files view stays current (Priority: P2)

**Goal**: a newly attached-and-sent file appears in the files view without a reload.

**Independent Test**: with the view showing a chat's files, send an attachment → it appears.

### Implementation

- [X] T019 [US3] `lib/presentation/pages/chat_card_page/bloc/chat_card_bloc.dart`: inject `MessageRepository`; on `_onInitialize` subscribe (once) to `watchMessages(_chatId).skip(1).debounceTime(100ms)` → `add(ChatCardEvent.initialize(_chatId))` (re-derive); cancel the subscription in `close()`. Scenario overrides unchanged.
- [X] T020 [P] [US3] Extend `test/presentation/pages/chat_card_page/bloc/chat_card_bloc_test.dart`: init for a chat (files present), then `getIt<MessageRepository>().sendMessage(chatId, attachment: <att>)` — the send persists a message (with the attachment) into `MessageDao`, so `watchMessages` ticks → after the debounce the bloc re-derives, the files list grows and the new file is first (newest-first), with no manual reload. (Per-test DB isolation as the reactive bloc tests use.)

**Checkpoint**: US3 — live files view.

---

## Phase 6: Polish & Cross-Cutting

- [X] T021 [P] Drift-fix (Principle II): update `docs/mock-completion-plan.md` §5.1/§5.2 + `docs/blueprints/mobile/04-data-layer.md` 016-seam note + `specs/016-*/data-model.md` reference — `ChatFilesRemoteDataSource` removed (chat files are a local derivation). Resolve the `_onAttachmentPicked`/`getChatFiles` `TODO`s.
- [X] T022 [P] Update the tracker `docs/mock-completion-plan.md`: flip F1 + E3 + R5 to done (at merge) with a §6 journal entry.
- [X] T023 Gate: `make gate` + `make golden-verify`; then the macOS native build check `make build-macos-stage` (verifies the file-access entitlement) + note iOS/Android/Windows/Linux for a CI build check. Walk `quickstart.md`.

---

## Dependencies & Execution Order

- **Setup** → **Foundational (T003–T005)** blocks stories. T003/T004 (mapper) ∥ T005 (seam).
- **US1** → after Foundational: T006 (impl) + T007 (entitlement) ∥; T008 (bloc) needs T005/T003; T009 generate after T006/T008; tests T010/T011 after.
- **US2** → after Foundational (independent of US1): T012 → T013 → T014 → T015 generate; tests T016/T017; T018 golden.
- **US3** → after US2 (needs the derived getChatFiles): T019 → T020.
- **Polish** → after the stories. T021 ∥ T022.

## Implementation Strategy

MVP = US1 (real picker). US2 (also P1) makes the files view real; US3 (P2) makes it live. `make generate` runs twice (US1 service/bloc; US2 repo constructor + removed bindings). Each phase leaves `make gate` green. One commit per story/phase (local only, never pushed). After all: multi-agent code review, fix findings, merge `017-file-attachments` → `develop` (`--no-ff`, no push), tick F1/E3/R5 in the tracker.

## Notes

- `file_selector` is the one new package (blueprint-planned). macOS verified locally; other platform builds flagged for CI.
- The picker seam returns `null` on cancel/failure → the composer is never corrupted and never crashes (FR-004/FR-009).
- The 5.4 golden regenerates (source change 8-fabricated → real derived); it is NOT a layout change. Tests run locally only (CI paused).
