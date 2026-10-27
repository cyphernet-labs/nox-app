# Contract: SessionRepository extension

Extends the existing `lib/domain/repository/app/session_repository.dart`. Implemented in `session_repository_impl.dart` (registered `@LazySingleton(as: SessionRepository, env: [dev, prod, test])`). No new package.

## New methods

```dart
/// Persists a new display label to the session (non-secret preferences store) and
/// broadcasts it on [watchLabel]. Does NOT touch the secure identifier. Caller
/// guarantees the label already passed validation (charset / uniqueness / ≤32).
Future<RepositoryResult<bool>> updateLabel({required String label});

/// Reactive display-label signal. Emits the current cached label on listen, then
/// every subsequent change (rename → new label, logout/clear → null). Broadcast:
/// multiple surfaces (shell avatar, future consumers) may listen concurrently.
Stream<String?> watchLabel();
```

## Behavioural contract

| Method | Guarantee |
|--------|-----------|
| `updateLabel` | Writes `preferences[session.label] = label`; emits `label` on `watchLabel`; returns `success(true)`. Never writes the secure identifier. On a store error returns `error(...)` and does not emit. |
| `watchLabel` | On listen, first emits the current cached label (`preferences[session.label]`, may be `null`). Thereafter emits on every `updateLabel` and on `clear` (emits `null`). A broadcast stream — supports N listeners; late listeners still get the current value first. |
| `clear` (existing) | In addition to its current wipe, emits `null` on `watchLabel` (logout resets every label surface to the fallback). |
| `saveIdentifier` / `setOnboardingComplete` (existing) | When called **with** a non-null `label`, also emit it on `watchLabel` (onboarding label is observable). Behaviour otherwise unchanged; the identifier write-order fail-safe in `saveIdentifier` is preserved. |

## Implementation notes

- `SessionRepositoryImpl` holds `final _labelController = StreamController<String?>.broadcast();`.
- `watchLabel()` is an `async*` that `yield`s the current cached label, then `yield*`s `_labelController.stream` — so each listener is seeded with the present value (same shape as `watchChats`).
- All emits go through a single private `_emitLabel(String?)` helper to keep the four writers (`updateLabel`, `clear`, `saveIdentifier`, `setOnboardingComplete`) consistent.
- Non-secret label read stays synchronous from `SharedPreferences`; the identifier read stays async from secure storage and is NOT needed for the label stream.

## Consumers

- `TabBarShell` — subscribes in `initState`, `setState`s `_accountLabel` (fallback `Constants.defaultUserLabel` on null/empty), cancels in `dispose`. Replaces `_loadAccountLabel` one-shot.
- `SettingsRootBloc._onNameSubmitted` — calls `updateLabel` on a confirmed valid rename.
- (Read path) `SettingsRootBloc._onInitialize` and `ChatThreadBloc`/`MessageRepositoryImpl` continue to use `readSession()` for the full aggregate + `resolveIdentity`.
