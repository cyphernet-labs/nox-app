---
description: "Task list for 016-remote-datasource-seam"
---

# Tasks: Remote-Data-Source Seam (mock data layer)

**Input**: Design documents from `specs/016-remote-datasource-seam/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: INCLUDED — 2 existing repo-test doubles retarget to the interface; 1 new rebinding test proves swappability. No new goldens (behaviour identical). The 5 `*Api` generator tests stay UNCHANGED and green (SC-003).

**Organization**: grouped by user story (US1 seam / US2 env-flip). Setup/Foundational/Polish carry no story label.

## Format: `[ID] [P?] [Story] Description`

## Path Conventions

Single Flutter package `nox_app`: source under `lib/`, tests deep-mirror under `test/`.

---

## Phase 1: Setup

- [X] T001 Confirm the pre-work baseline is green on branch `016-remote-datasource-seam`: `make gate` (609) + `make golden-verify` (144); record counts so post-refactor deltas are attributable (target: identical counts — behaviour unchanged).

---

## Phase 2: Foundational (Blocking Prerequisites) — the interfaces

**Purpose**: the seam types. Both the mock impls and the repos depend on them.

**⚠️ CRITICAL**: no story work until these exist.

- [X] T002 [P] Add `lib/data/remote/datasource/chat_remote_data_source.dart`: `abstract class ChatRemoteDataSource { Future<(List<ChatModel>, PageMetadata)> getChats({required GetChatsConfig config}); }` (signature mirrors `GetChatsApi.execute`).
- [X] T003 [P] Add `lib/data/remote/datasource/chat_files_remote_data_source.dart`: `abstract class ChatFilesRemoteDataSource { Future<List<MessageAttachment>> getChatFiles({required String chatId}); }`.
- [X] T004 [P] Add `lib/data/remote/datasource/message_remote_data_source.dart`: `abstract class MessageRemoteDataSource` with `getMessages({required GetMessagesConfig config})` and `sendMessage({required String chatId, required String authorId, required String authorLabel, String? text, MessageAttachment? attachment})` (FR-009, mirrors `GetMessagesApi`/`SendMessageApi`).
- [X] T005 [P] Add `lib/data/remote/datasource/item_remote_data_source.dart`: `abstract class ItemRemoteDataSource { Future<ResponseEntity<ItemsEntity>> getItems({required GetItemsConfig config}); }`.

**Checkpoint**: interfaces exist — mocks + repos can bind.

---

## Phase 3: User Story 1 - Repositories depend on a seam, not a concrete mock (Priority: P1) 🎯 MVP

**Goal**: the four mock data sources implement the interfaces (delegating to the unchanged `*Api` generators); every repository depends on the interface; behaviour is byte-for-byte unchanged.

**Independent Test**: grep — 0 repositories reference a concrete `*Api`; the full suite passes unchanged.

### Implementation

- [X] T006 [P] [US1] Add `lib/data/remote/datasource/mock/mock_chat_remote_data_source.dart`: `MockChatRemoteDataSource implements ChatRemoteDataSource`, injects `GetChatsApi`, `getChats(config) => _api.execute(config: config)`, annotated `@LazySingleton(as: ChatRemoteDataSource, env: [Environment.dev, Environment.prod, Environment.test])`. Add a doc comment pointing to the flip recipe (`contracts/di-binding.md`).
- [X] T007 [P] [US1] Add `mock_chat_files_remote_data_source.dart`: `MockChatFilesRemoteDataSource` delegating to `GetChatFilesApi.execute(chatId:)`, same env annotation.
- [X] T008 [P] [US1] Add `mock_message_remote_data_source.dart`: `MockMessageRemoteDataSource` injecting `GetMessagesApi` + `SendMessageApi`, forwarding `getMessages`/`sendMessage`, same env annotation.
- [X] T009 [P] [US1] Add `mock_item_remote_data_source.dart`: `MockItemRemoteDataSource` delegating to `GetItemsApi.execute(config:)`, same env annotation.
- [X] T010 [US1] Repoint `lib/data/repository/chat/chat_repository_impl.dart`: constructor deps `GetChatsApi`/`GetChatFilesApi` → `ChatRemoteDataSource`/`ChatFilesRemoteDataSource`; call sites `_getChatsApi.execute(config:)` → `_chatRemote.getChats(config:)`, `_getChatFilesApi.execute(chatId:)` → `_chatFilesRemote.getChatFiles(chatId:)`. No logic change.
- [X] T011 [US1] Repoint `lib/data/repository/chat/message_repository_impl.dart`: replace the two deps `GetMessagesApi` + `SendMessageApi` with one `MessageRemoteDataSource`; call sites → `.getMessages(config:)` / `.sendMessage(...)`. (Session/DAO/mapper deps unchanged.)
- [X] T012 [US1] Repoint `lib/data/repository/item/item_repository_impl.dart`: dep `GetItemsApi` → `ItemRemoteDataSource`; call site → `.getItems(config:)`.
- [X] T013 [US1] Run `make generate` — regenerate `configure_dependencies.config.dart` (new `as:` bindings + repo constructor changes). Confirm the generated graph wires each repo to its mock impl via the interface. (depends on T006–T012)
- [X] T014 [US1] Retarget `test/data/repository/chat/message_repository_impl_test.dart` forced-failure case: `@GenerateMocks([MessageRemoteDataSource])`; stub `sendMessage(...)` to throw; construct `MessageRepositoryImpl` with the mock data source (constructor now takes one `MessageRemoteDataSource` instead of two `*Api`). Re-run `make generate` for the new `*.mocks.dart`.
- [X] T015 [US1] Retarget `test/data/repository/item/item_repository_impl_test.dart`: `@GenerateMocks([ItemRemoteDataSource])`; stub `getItems(...)`; construct `ItemRepositoryImpl(mapper, mockItemRemote)`. Re-run `make generate`.
- [X] T016 [US1] Verify SC-003: run the 5 `*Api` generator tests (`test/data/remote/api/**`) + repo happy-path tests + a broad slice — all green with NO behavioural assertion edits (only the two doubles above changed wiring).

**Checkpoint**: the seam is in place, behaviour unchanged.

---

## Phase 4: User Story 2 - Mock↔real is an environment-scoped config flip (Priority: P1)

**Goal**: prove the binding is interface-based + env-scoped so a real impl swaps in via DI alone; document the flip.

**Independent Test**: a rebinding test routes a repository through a fake interface impl with zero repo edits.

### Implementation

- [X] T017 [US2] Add `test/data/remote/datasource/seam_binding_test.dart`: with the test-env DI + a clean DB, register a `_FakeChatRemoteDataSource` (returns a sentinel `('SENTINEL' chat, PageMetadata)`) via `getIt.allowReassignment` + `registerSingleton<ChatRemoteDataSource>` BEFORE first resolving `ChatRepository`; assert `getIt<ChatRepository>().getChats(firstPage)` surfaces the sentinel — the repo routed through the rebound interface (SC-002).
- [X] T018 [US2] Confirm the env-scoping is production-safe: verify every mock impl is `env: [dev, prod, test]` (grep) and `flutter analyze` is clean (the prod flavor boots `Environment.prod` → must resolve the mock; FR-007). The ≤3-step flip recipe is already in `contracts/di-binding.md` + `quickstart.md`; ensure each mock impl's doc comment references it (SC-006).

**Checkpoint**: swappability proven, flip documented.

---

## Phase 5: Polish & Cross-Cutting

- [X] T019 [P] Drift-fix docs (Principle II): update `docs/mock-completion-plan.md` §5.1 (inventory — repos now depend on `*RemoteDataSource`, not concrete mocks) + §5.2 (seam reality) and add a blueprint `docs/blueprints/mobile/04-data-layer.md` note on the remote-data-source seam + the flip recipe.
- [X] T020 [P] Update the tracker task table `docs/mock-completion-plan.md`: flip S1 + S2 to done (at merge) with a §6 journal entry (files, counts, "merged into develop, not pushed").
- [X] T021 Gate: `make gate` + `make golden-verify` (144 unchanged); grep to confirm SC-001 (0 repositories reference a concrete `*Api`). Walk `quickstart.md` checks.

---

## Dependencies & Execution Order

- **Setup** → no deps.
- **Foundational (interfaces T002–T005)** → after Setup; block all stories; all `[P]` (distinct files).
- **US1** → after Foundational. Mock impls T006–T009 `[P]` (distinct files); repo repoints T010–T012 `[P]` (distinct files) but all need the interfaces; T013 generate after all lib edits; T014/T015 retarget doubles (each re-generates mocks); T016 verify.
- **US2** → after US1 (needs the bindings + repos). T017 rebinding test; T018 env-scoping confirm.
- **Polish** → after the stories. T019 ∥ T020.

## Implementation Strategy

MVP = US1 (the seam itself). US2 (P1) proves + documents the flip. Each phase leaves `make gate` + `make golden-verify` green. One commit per phase (Foundational+US1 together — they compile as a unit; then US2; then Polish) — local only, never pushed. After all: multi-agent code-review of the diff, fix findings, merge `016-remote-datasource-seam` → `develop` (`--no-ff`, no push), tick S1/S2 in the tracker.

## Notes

- `make generate` runs twice: once for DI after the repo/mock changes (T013), once for the retargeted `@GenerateMocks` (T014/T015). Generated `*.config.dart`/`*.mocks.dart` are gitignored.
- Behaviour is byte-for-byte unchanged — the `*Api` generators and every golden are untouched. Any test count change is only the +1 new rebinding test.
- Tests run **locally only** (CI paused) — `make gate` + `make golden-verify` are the sole regression net.
