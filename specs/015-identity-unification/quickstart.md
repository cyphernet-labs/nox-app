# Quickstart & Validation: Unified Signed-In Identity (mocks)

How to prove the feature end-to-end. Backend stays mocked; everything runs on the local session store + Sembast.

## Prerequisites

- `make deps` (once) and `make generate` if freezed/injectable inputs changed.
- Run the app on a desktop target to exercise the rail avatar (US3): `fvm flutter run -d macos --dart-define-from-file=config/stage.json`.

## Automated validation (the gate)

```bash
make gate            # generate → format → analyze → test (goldens excluded)
make golden-verify   # must stay green — this feature adds NO new goldens
```

Targeted suites:

```bash
make test FILE=test/general/identity/identity_resolver_test.dart
make test FILE=test/data/repository/app/session_repository_impl_test.dart
make test FILE=test/data/repository/chat/message_repository_impl_test.dart
make test FILE=test/presentation/pages/settings_root_page/bloc/settings_root_bloc_test.dart
make test FILE=test/presentation/pages/chat_thread_page/bloc/chat_thread_bloc_test.dart
make test FILE=test/presentation/widgets/shell/tab_bar_shell_identity_test.dart
```

## Manual validation

### US1 — own messages carry my identity
1. Sign in (onboarding) so a session with a label exists.
2. Open any chat. **Expect**: the seeded own messages ("Thanks! Happy to be here.", "Agree…", etc.) render on the **own** (right) side; other authors (Aria/Mox/Kit) on the left.
3. Send a new message. **Expect**: it appears on the own side and acks to `sent`.

### US2 — Settings shows & remembers my name
1. Open **Settings** → identity card. **Expect**: the name field shows your chosen label (not `User7421`, unless that is genuinely your label).
2. Edit the name to a valid, available value (e.g. `Alice2`) and confirm (Enter/Done/blur). **Expect**: the card shows `Alice2`.
3. Fully quit and relaunch the app; reopen Settings. **Expect**: still `Alice2` (persisted).
4. Try an invalid (`bad name!`) or taken label. **Expect**: rejected inline; nothing persisted.

### US3 — a rename updates every surface live
1. On a **desktop-width** window, note the navigation-rail account avatar (its initials come from your label).
2. In the Settings tab, rename your label and confirm. **Expect**: the rail avatar updates to the new label's initials **within ~1s, without restart**.
3. Start an edit, then cancel it. **Expect**: the rail avatar does **not** change.

## Success-criteria mapping

| Criterion | Validated by |
|-----------|--------------|
| SC-001 (Settings shows chosen label) | US2 step 1 · `settings_root_bloc_test` load case |
| SC-002 (rename survives restart) | US2 step 3 · `session_repository_impl_test` updateLabel + re-read |
| SC-003 (rail avatar ≤1s, no restart) | US3 step 2 · `tab_bar_shell_identity_test` |
| SC-004 (all surfaces agree) | US2 + US3 · single broadcast source |
| SC-005 (own/other correct) | US1 · `chat_thread_bloc_test` + `message_repository_impl_test` seed reconcile |
| SC-006 (rename never reclassifies) | detection identifier-keyed · `chat_thread_bloc_test` rename-invariance case |

## Rollback / safety

- No schema migration; no network. Reverting the branch restores the placeholder constants with no data cleanup needed.
- Logout still fully wipes identity + caches (unchanged); `watchLabel` emits `null` → surfaces fall back to the default.
