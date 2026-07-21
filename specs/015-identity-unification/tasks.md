---
description: "Task list for 015-identity-unification"
---

# Tasks: Unified Signed-In Identity (mocks)

**Input**: Design documents from `specs/015-identity-unification/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: INCLUDED — the project mandates test coverage (blueprint) and plan.md/research R6 enumerate the suites. No new goldens (behavioural feature; `make golden-verify` must stay green).

**Organization**: grouped by user story (US1/US2/US3) for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on incomplete tasks)
- **[Story]**: US1 / US2 / US3 (Setup & Foundational & Polish carry no story label)

## Path Conventions

Single Flutter package `nox_app`: source under `lib/`, tests deep-mirror under `test/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: establish a clean, green baseline before touching code.

- [X] T001 Confirm the pre-work baseline is green on branch `015-identity-unification`: run `make gate` and `make golden-verify` (144 goldens) and record the passing test count so post-feature deltas are attributable.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the single identity source + the reactive label channel. Shared by ALL three stories.

**⚠️ CRITICAL**: no user story may begin until this phase is complete.

- [X] T002 Repurpose `lib/general/identity_mock_data.dart`: add `static const String fallbackOwnId = 'me';` and rewrite the doc-comment to describe the no-session sentinel + seed raw own-author role. Keep the existing `currentUserId`/`currentLabel` constants for now (removed in T012 once all refs migrate) so the tree keeps compiling.
- [X] T003 Add the pure resolver in `lib/general/identity/identity_resolver.dart`: `typedef Identity = ({String id, String label});` and `Identity resolveIdentity(SessionModel? session)` → `id = (session?.identifier non-empty) ? identifier : IdentityMockData.fallbackOwnId`, `label = (session?.label non-empty) ? label : Constants.defaultUserLabel`. Pure, no I/O. (depends on T002)
- [X] T004 [P] Unit test `test/general/identity/identity_resolver_test.dart`: null session → (`me`, `User7421`); full session → passthrough; empty label → default; empty identifier → fallback id; non-empty passthrough. (depends on T003)
- [X] T005 Extend the interface `lib/domain/repository/app/session_repository.dart`: add `Future<RepositoryResult<bool>> updateLabel({required String label});` and `Stream<String?> watchLabel();` with the doc from `contracts/session-repository.md`.
- [X] T006 Implement the broadcast in `lib/data/repository/app/session_repository_impl.dart`: a `StreamController<String?>.broadcast()` + private `_emitLabel`; `updateLabel` writes `preferences[label]` then emits; `watchLabel` is `async*` (yield current cached label, then `yield* controller.stream`); wire `clear` to emit `null` and `saveIdentifier`/`setOnboardingComplete` to emit the label when one is provided. Preserve the identifier write-order fail-safe. (depends on T005)
- [X] T007 [P] Repo test `test/data/repository/app/session_repository_impl_test.dart`: `updateLabel` persists (re-read reflects the new label) and does NOT touch the identifier; `watchLabel` emits the current label on listen, then the new label after `updateLabel`, then `null` after `clear`. (depends on T006)

**Checkpoint**: identity source + reactive label channel ready — stories can start.

---

## Phase 3: User Story 1 - My own messages carry my real identity (Priority: P1) 🎯 MVP

**Goal**: the chat thread resolves its own-identity from the session; seeded own history + new sends are attributed to that identity; own-vs-other stays correct and rename-invariant. Removes the `me`/`You` placeholders.

**Independent Test**: sign in, open a chat with mixed authors → own seed messages render on the own side, others on the other side; a new send lands own.

### Implementation

- [X] T008 [US1] Make `lib/data/remote/api/chat/send_message_api.dart` a dumb echo: add required `authorId` / `authorLabel` params to `execute`, use them in the returned `MessageModel`, and drop the `IdentityMockData` import.
- [X] T009 [US1] Wire the session into `lib/data/repository/chat/message_repository_impl.dart`: inject `SessionRepository`; resolve `identity = resolveIdentity((await sessionRepository.readSession()).data)`; in `_seedChatIfEmpty` rewrite seed rows where `authorId == IdentityMockData.fallbackOwnId` to `identity.id` before persisting; in `sendMessage` pass `identity.id`/`identity.label` to `SendMessageApi.execute`. (constructor change → codegen in T012) (depends on T008, T003)
- [X] T010 [US1] In `lib/data/remote/api/chat/get_messages_api.dart` key the own `status` check on `IdentityMockData.fallbackOwnId` (the seed keeps its literal `me` own-author tuples).
- [X] T011 [US1] In `lib/presentation/pages/chat_thread_page/bloc/chat_thread_bloc.dart` `_onInitialize`: read the session, set `currentId = resolveIdentity(session).id` (fallback id on absent/failed read — thread still renders), and author the optimistic send with `resolveIdentity(session).label`; remove `IdentityMockData.currentUserId`/`currentLabel` usages. (depends on T003)
- [X] T012 [US1] Remove the now-unused `IdentityMockData.currentUserId`/`currentLabel` and refresh the `lib/domain/model/chat/message_model.dart` doc-comment (own = `authorId == resolved session id`). Run `make generate` (picks up the T009 constructor change). (depends on T009, T010, T011)
- [X] T013 [P] [US1] Extend `test/data/repository/chat/message_repository_impl_test.dart`: with a session present, first-open seed own rows carry the session identifier (not `me`); `sendMessage` authors the persisted message with the session identity. (depends on T009)
- [X] T014 [P] [US1] Extend `test/presentation/pages/chat_thread_page/bloc/chat_thread_bloc_test.dart`: `currentId` equals the session identifier when a session exists; own seed history + a new send both classify as own; a label change does NOT change any message's own/other side (identifier-keyed). (depends on T011)

**Checkpoint**: US1 fully functional and independently testable.

---

## Phase 4: User Story 2 - Settings shows and remembers my chosen name (Priority: P1)

**Goal**: the Settings identity card loads the session label and a confirmed valid rename persists to the session (survives restart). Existing validation is the unchanged pre-persist gate.

**Independent Test**: open Settings → shows the chosen label; rename to a valid value → restart → still shows the renamed value.

### Implementation

- [X] T015 [US2] In `lib/presentation/pages/settings_root_page/bloc/settings_root_bloc.dart` `_onInitialize`: set `name = resolveIdentity(session).label` from the loaded session (keep the `rawId` load unchanged, still degrading to empty on error). (depends on T003)
- [X] T016 [US2] Make `_onNameSubmitted` async in the same file: on `canSave`, `await sessionRepository.updateLabel(label: state.draftName)`; on success emit `copyWith(name: draftName, editing: false, status: idle)`; on error keep the edit open (do not show a saved name that failed to persist). Update the class doc TODO. (depends on T006)
- [X] T017 [P] [US2] Extend `test/presentation/pages/settings_root_page/bloc/settings_root_bloc_test.dart`: initialize loads the session label into `name`; a valid confirmed rename calls `updateLabel` and a subsequent `readSession` reflects it; an invalid/taken draft never reaches `updateLabel` (no persistence). (depends on T015, T016)

**Checkpoint**: US1 + US2 both work independently.

---

## Phase 5: User Story 3 - A rename updates every surface live (Priority: P2)

**Goal**: the desktop rail account avatar (and any live label surface) updates immediately on a rename, no restart — via the `watchLabel` broadcast.

**Independent Test**: on a desktop-width window, rename in Settings → the rail avatar reflects the new label within ~1s.

### Implementation

- [X] T018 [US3] In `lib/presentation/widgets/shell/tab_bar_shell_widget.dart` replace the one-shot `_loadAccountLabel` with a `sessionRepository.watchLabel()` subscription: on each emit `setState(_accountLabel = (label?.isNotEmpty == true) ? label! : Constants.defaultUserLabel)`; store the `StreamSubscription` and cancel it in `dispose`; update the `_accountLabel` doc-comment (now live, not one-shot). (depends on T006)
- [X] T019 [P] [US3] New widget test `test/presentation/widgets/shell/tab_bar_shell_identity_test.dart`: pump `TabBarShell` on a desktop-width surface with a session labelled `Alice`; assert the rail avatar shows `A`; call `getIt<SessionRepository>().updateLabel(label: 'Zed')`; pump; assert the rail avatar updates to `Z` without a rebuild of the whole app. (depends on T018)

**Checkpoint**: all three stories independently functional.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: drift-fixes (Principle II), tracker, and the final gate.

- [X] T020 [P] Drift-fix docs & comments (same change-set): add a short note to `docs/blueprints/mobile/04-data-layer.md` (session label as a reactive change-signal) and reconcile the `TODO(backend): live label` comments in `tab_bar_shell_widget.dart` / `settings_root_bloc.dart` / `identity_mock_data.dart` to describe the now-real behaviour.
- [X] T021 [P] Update the tracker `docs/mock-completion-plan.md`: flip D3 + R4 to done (at merge) with a §6 journal entry (files touched, test/golden counts, "merged into develop, not pushed").
- [X] T022 Run the gate: `make gate` (generate → format changed paths `-l 140` → analyze zero-errors → test) and `make golden-verify` (must stay at 144 — no new goldens). Then walk `quickstart.md` US1/US2/US3 manual checks.

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (P1)** → no deps.
- **Foundational (P2)** → after Setup; **blocks all stories**. Internal order: T002 → T003 → (T004); T005 → T006 → (T007). The resolver (T003) and the repo channel (T006) are independent tracks and may proceed in parallel.
- **US1 (P3)** → after Foundational. Order: T008 → T009; T010, T011 in parallel with T009 (different files); T012 after T009/T010/T011; tests T013/T014 after their impl.
- **US2 (P4)** → after Foundational (needs T003 + T006). Independent of US1.
- **US3 (P5)** → after Foundational (needs T006). Independent of US1/US2 (testable by calling `updateLabel` directly).
- **Polish (P6)** → after the stories being delivered.

### Parallel opportunities

- T004 ∥ (rest of foundational once T003 done); the resolver track (T002→T003→T004) ∥ the repo track (T005→T006→T007).
- Within US1: T010 ∥ T011 ∥ T008 (distinct files); T013 ∥ T014.
- Across stories: once Foundational is done, US1 / US2 / US3 can be built in parallel (disjoint files: message-repo/thread vs settings-bloc vs shell).
- Polish T020 ∥ T021.

## Implementation Strategy

### MVP (US1)

Setup → Foundational → US1 → validate own/other classification independently. US1 is the 🎯 MVP; US2 (also P1) is the natural next increment; US3 (P2) is the live-broadcast polish.

### Incremental delivery

Foundational → US1 (own identity) → US2 (persist) → US3 (live broadcast). Each leaves `make gate` + `make golden-verify` green and is independently demoable.

### Commit strategy (repo policy)

One commit per completed story/phase (Foundational, US1, US2, US3, Polish) — local only, **never pushed**. After all stories: run code-review over the diff, fix findings, merge `015-identity-unification` → `develop` (`--no-ff`, no push), tick D3/R4 in the tracker.

## Notes

- No new package, no schema migration, no network. `make generate` needed once (T012) for the `MessageRepositoryImpl` constructor change.
- No new goldens — the feature changes *which value* flows into locked layouts, not the layouts. `make golden-verify` staying at 144 is part of the gate.
- Tests run **locally only** (CI paused) — `make gate` + `make golden-verify` are the sole regression net.
