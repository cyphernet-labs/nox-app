# Data Model: Unified Signed-In Identity (mocks)

No new persisted schema — this feature re-wires *reads/writes* of the existing session store and reconciles seeded message rows. It introduces one in-memory value object and one resolution rule.

## Entities

### Identity (in-memory value object) — NEW

The resolved signed-in identity handed to consumers. Not persisted; derived from `SessionModel`.

| Field | Type | Notes |
|-------|------|-------|
| `id` | `String` | The own-identity id used for own-vs-other detection and as `authorId` of own messages. `= session.identifier` when a session exists, else `IdentityMockData.fallbackOwnId` (`'me'`). Stable for the life of the local DB. |
| `label` | `String` | The display label. `= session.label` when non-empty, else `Constants.defaultUserLabel` (`'User7421'`). |

Representation: a lightweight record `({String id, String label})` returned by `resolveIdentity`, or a small immutable `Identity` class in `lib/domain/model/app/identity.dart`. No Freezed/codegen needed (two final fields).

### SessionModel (existing) — unchanged shape

`{ String identifier; String? label; bool onboardingComplete }`. This feature adds *write* (`label` mutation via `updateLabel`) and *observe* (`watchLabel`) paths; the shape is not modified. `identifier` remains rename-invariant.

### Message authorship (existing `MessageModel`) — reconciled, not reshaped

`MessageModel.authorId` / `authorLabel` are unchanged fields. What changes:
- **Own seed rows**: authored with `IdentityMockData.fallbackOwnId` by the mock, **rewritten to the resolved `id`** at seed time before persistence.
- **New own sends**: `authorId = resolved id`, `authorLabel = resolved label` (from the session at send time).
- **Other rows**: untouched.

## Resolution rule (single source)

```
resolveIdentity(SessionModel? s):
    id    = (s?.identifier is non-empty) ? s.identifier : IdentityMockData.fallbackOwnId
    label = (s?.label      is non-empty) ? s.label      : Constants.defaultUserLabel
    return (id, label)
```

Consumed by: `ChatThreadBloc` (own `currentId` + optimistic author label) and `MessageRepositoryImpl` (seed reconcile + send authoring). Because both call the same rule, the thread's `currentId` and the seeded own rows always share one id.

### Constants / sentinels

| Name | Location | Value | Role |
|------|----------|-------|------|
| `IdentityMockData.fallbackOwnId` | `IdentityMockData` (repurposed) | `'me'` | No-session own-id sentinel; also the mock seed's raw own-author. |
| label fallback | `Constants.defaultUserLabel` | `'User7421'` | Unified display fallback (replaces the dropped `You` label sentinel). |

`IdentityMockData.currentUserId` / `currentLabel` are **removed** and replaced by `IdentityMockData.fallbackOwnId`; references (`get_messages_api`, `chat_thread_bloc`, `send_message_api`, `message_model` doc) are updated.

## State transitions

### Display label lifecycle

```
onboarding sets label ──► preferences[label] set ──► watchLabel emits label
        │
        ▼
Settings rename (valid, confirmed) ──► updateLabel(newLabel)
        │                                   │
        │                                   ├─► preferences[label] = newLabel
        │                                   └─► broadcast: watchLabel emits newLabel
        ▼                                              │
Settings state.name = newLabel                         ▼
                                          shell _accountLabel = newLabel (setState)
        │
        ▼
logout / clear ──► preferences[label] removed ──► watchLabel emits null ──► shell → default fallback
```

Invariants:
- A rename never writes `identifier` (own/other classification is immutable across a rename — FR-011).
- An empty/absent label always resolves to the default fallback, never a blank display.
- Every on-screen label surface converges to the last emitted value (single broadcast source — SC-004).

## Validation rules (unchanged, enforced pre-persist)

Display label: case-sensitive unique · `≤32` chars · charset `[A-Za-z0-9._-]` · non-empty. Enforced by `UsernameRules` + the debounced availability check before `canSave`; `updateLabel` is only called for a `canSave` draft.
