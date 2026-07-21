# Research: Unified Signed-In Identity (mocks)

Phase 0 decisions. Each resolves an open choice from the spec Assumptions, grounded in the existing `lib/` code.

## R1 — Where does the single identity source live?

**Decision**: Extend the existing **`SessionRepository`** (identifier in secure storage, label/onboarding in preferences) rather than introduce a parallel `IdentityRepository`. Add a pure **`resolveIdentity(SessionModel?)`** util for the fallback-resolution rule.

**Rationale**: The session already *is* the identity aggregate (`SessionModel{identifier, label, onboardingComplete}`) and is reached everywhere via the `sessionRepository` global alias. A new repository would duplicate the store and the wiring. Keeping resolution in one pure function (not scattered `?? 'me'` expressions) guarantees the thread and the seed agree.

**Alternatives considered**:
- *New `IdentityRepository` wrapping the session* — more classes, no new capability; rejected as over-abstraction for the mock phase.
- *Shell-local `ValueNotifier` broadcast* (like `_chatsScrollToTop`) — identity is cross-cutting (thread + settings + shell), not shell-local; a repository stream is the blueprint-aligned cross-cutting channel.

## R2 — How is a rename broadcast live to the shell?

**Decision**: A **broadcast label stream** on `SessionRepository`: `Stream<String?> watchLabel()` that emits the current cached label on listen, then every change. `updateLabel({required String label})` persists to preferences and emits; `clear()` (logout) emits `null`. The BLoC-less `TabBarShell` subscribes in `initState` and `setState`s on each emit (fallback to `Constants.defaultUserLabel` for null/empty); it cancels in `dispose`.

**Rationale**: Directly mirrors feature-014's established "watch as a change-signal over the cache" pattern (`watchChats`/`watchMessages`). The shell already performs a one-shot `sessionRepository.readSession()` + `setState` under the documented 05 §5.1 UI-first carve-out; upgrading that to a subscription is the smallest consistent step and needs no shell BLoC yet.

**Alternatives considered**:
- *`watchSession()` emitting `SessionModel?`* — would require an async secure-storage read on every emit to rebuild the identifier; the shell only needs the label. `watchLabel()` emits the label string synchronously from the controller. (A `watchSession()` can be added later if another surface needs the whole aggregate.)
- *Polling / re-read on tab focus* — laggy, misses the "within 1s" target, and is not reactive.

**Implementation note**: `SessionRepositoryImpl` holds a `StreamController<String?>.broadcast()`. `watchLabel()` is `async* { yield <current cached label>; yield* controller.stream; }` so every new listener gets the current value first (matches `watchChats` seed-then-live). The identifier write-order invariant in `saveIdentifier` is untouched.

## R3 — How does seeded own-history stay "own" once the own-id comes from the session?

**Decision**: **Reconcile at seed time.** `GetMessagesApi` keeps authoring own seed rows with the sentinel `me` (= `kFallbackOwnId`). `MessageRepositoryImpl._seedChatIfEmpty` rewrites any row whose `authorId == kFallbackOwnId` to the **resolved own-id** (`session?.identifier ?? kFallbackOwnId`) before persisting. The thread's `currentId` uses the *same* resolver, so seeded own rows and new own sends share one identifier.

**Rationale**: The identifier is **stable for the life of the local DB**. It is written once at onboarding and only changes on logout; logout (feature D1) wipes the chat + message caches, so the next open re-seeds against the new identity. There is therefore no "seeded under identity A, later read under identity B" window in the real flow. Seed-time reconcile is both correct and cheap (one rewrite pass on first open).

**Alternatives considered**:
- *Read-time reconcile / dual own-check (`id == currentId || id == 'me'`)* — leaks the sentinel into detection logic forever and re-runs on every read; rejected.
- *Bake the identifier into `GetMessagesApi`* — the mock source would need the session injected; keeping the API a pure deterministic echo and reconciling in the repository is cleaner separation.

## R4 — What are the fallbacks when no session exists (tests / degraded read)?

**Decision**: `resolveIdentity(null)` returns `(id: kFallbackOwnId /* 'me' */, label: Constants.defaultUserLabel /* 'User7421' */)`. An empty stored label is treated as absent (→ default). The label fallback is unified to `Constants.defaultUserLabel`; the old thread label sentinel `You` is dropped.

**Rationale**: Own-detection needs a stable non-empty id; `'me'` matches the un-reconciled seed, so a no-session thread still renders coherently (all tests without a seeded session keep passing). The scannable `Your ID` is a *separate* concern (`SettingsRootState.rawId`) and still degrades to empty on a failed read — a fabricated id must never flow into a real QR (Principle I).

## R5 — Rename persistence + validation reuse

**Decision**: `SettingsRootBloc._onNameSubmitted` becomes async: on `canSave`, call `sessionRepository.updateLabel(label: draftName)`, then emit the new `name`. The existing charset + case-sensitive uniqueness gate (`UsernameRules`, debounced availability check) is unchanged and remains the pre-persist guard — an invalid/taken draft never reaches `canSave`. `_onInitialize` additionally loads `session.label` into `name`.

**Rationale**: Reuses the proven 2.3/7.1 validation vocabulary; the only new behaviour is the persistence call and the initial label load. No new uniqueness backend (mock phase).

**Alternatives considered**:
- *Persist on every keystroke* — would broadcast churn and defeat validation; rejected. Persist only on confirmed, valid submit.

## R6 — Testing & goldens

**Decision**: Behavioural coverage only — a new pure-util test (`resolveIdentity`), repository tests (`updateLabel` persists + `watchLabel` emits; message-repo seed reconcile + send authoring), bloc tests (Settings load + persist; thread `currentId` from session), and one widget test (shell rail avatar updates live on a rename broadcast). **No new goldens** and no changes to existing golden layouts — the thread bubbles and the avatar are visually unchanged (own bubbles never render a label; the avatar's initials logic is already golden-covered). `make golden-verify` must stay green.

**Rationale**: The feature changes *which value* flows into already-locked layouts, not the layouts themselves. Adding goldens would lock content that legitimately varies by session and add no regression protection.
