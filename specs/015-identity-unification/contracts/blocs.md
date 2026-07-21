# Contract: BLoC / shell behaviour changes

No new events or states — existing handlers gain identity-from-session behaviour.

## SettingsRootBloc (`presentation/pages/settings_root_page/bloc/`)

**`_onInitialize`** — additionally loads the display label:
- Read `session.label`; set `state.name = resolveIdentity(session).label` (session label, else `Constants.defaultUserLabel`). `rawId` load is unchanged (degrades to empty).
- Acceptance: entering Settings for a session labelled `Alice` shows `name == 'Alice'` (SC-001, US2-1).

**`_onNameSubmitted`** — now persists (becomes async):
- Guard `if (!state.canSave) return;` (unchanged).
- `await sessionRepository.updateLabel(label: state.draftName)`.
- On success: `emit(state.copyWith(name: draftName, editing: false, status: idle))`.
- On error: keep the draft/editing open (mock never errors; defensive only) — do not claim a persisted name that failed to save.
- Acceptance: after a valid confirmed rename, `readSession().label == draftName`; survives restart (US2-2/US2-3, SC-002).

**Validation** — unchanged. `NameChanged`/`AvailabilityRequested` charset + case-sensitive uniqueness gate stays; an invalid/taken draft never reaches `canSave`, so `updateLabel` is never called for it (US2-4, FR-008).

## ChatThreadBloc (`presentation/pages/chat_thread_page/bloc/`)

**`_onInitialize`** — own-identity from the session (replaces `IdentityMockData.currentUserId`):
- Read the session (`sessionRepository.readSession()`), resolve `currentId = resolveIdentity(session).id` before emitting `Initialized(currentId: currentId)`.
- A failed/absent read → `currentId = fallbackOwnId` (thread still renders; FR-014).
- The `markChatRead` + `watchMessages` reactive wiring (feature 014) is unchanged.

**`_onMessageSent`** — optimistic bubble `authorId = current.currentId`, `authorLabel = resolveIdentity(session).label` (or the session label captured at init). The persisted send (via the repository) is the authority and is adopted by `_adoptOutgoing`.
- Acceptance: own seed history + new sends all render on the own side (US1-1/US1-2, SC-005); own/other classification never changes on a rename (US1, FR-011/SC-006 — detection is identifier-keyed).

## TabBarShell (`presentation/widgets/shell/tab_bar_shell_widget.dart`)

**Live label subscription** (replaces the one-shot `_loadAccountLabel`):
- In `initState`, subscribe to `sessionRepository.watchLabel()`. On each emit: `setState(_accountLabel = (label?.isNotEmpty == true) ? label : Constants.defaultUserLabel)`.
- Cancel the subscription in `dispose`.
- Acceptance: renaming in the Settings tab updates the desktop rail account avatar within ~1s, no restart (US3-1, SC-003); a rejected/abandoned edit changes nothing (US3-3).
- Remains BLoC-less under the documented 05 §5.1 UI-first carve-out (subscription is a minimal extension of the already-present repo read); a full shell value-BLoC is the backend-phase migration.

## MessageRepositoryImpl / SendMessageApi (`data/`)

- `MessageRepositoryImpl` injects `SessionRepository`; `_seedChatIfEmpty` reconciles seed own rows (`authorId == fallbackOwnId → resolved id`); `sendMessage` resolves the identity and authors the persisted message with it.
- `SendMessageApi.execute` gains `authorId` / `authorLabel` params (dumb echo) — no longer references `IdentityMockData`.
- `get_messages_api` keeps the `me` seed literal but keys the own `status` check on `IdentityMockData.fallbackOwnId`.
