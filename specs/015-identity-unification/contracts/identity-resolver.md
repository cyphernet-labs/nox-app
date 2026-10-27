# Contract: identity resolver + fallback sentinels

The single resolution rule that turns a (possibly absent) session into a concrete own-identity. Pure, synchronous, no I/O.

## Location

`lib/general/identity/identity_resolver.dart` (pure util) + repurposed `lib/general/identity_mock_data.dart` (sentinel). Optional `lib/domain/model/app/identity.dart` if a named value object is preferred over a record.

## API

```dart
/// The signed-in own-identity resolved from the local session, with mock-phase
/// fallbacks for the no-session / degraded-read case.
typedef Identity = ({String id, String label});

/// Resolves the own-identity used for own-vs-other detection and own-message
/// authorship. `id` falls back to [IdentityMockData.fallbackOwnId]; `label` to
/// [Constants.defaultUserLabel]. An empty stored value is treated as absent.
Identity resolveIdentity(SessionModel? session);
```

```dart
// lib/general/identity_mock_data.dart  (repurposed)
abstract final class IdentityMockData {
  const IdentityMockData._();

  /// No-session own-id sentinel; ALSO the raw own-author the mock seed emits,
  /// so seed rows and a no-session thread resolve to the same id.
  static const String fallbackOwnId = 'me';
}
```

## Behavioural contract

| Input | `id` | `label` |
|-------|------|---------|
| `null` (no session) | `fallbackOwnId` (`'me'`) | `Constants.defaultUserLabel` (`'User7421'`) |
| `SessionModel(identifier: 'abc', label: 'Alice')` | `'abc'` | `'Alice'` |
| `SessionModel(identifier: 'abc', label: null)` | `'abc'` | `Constants.defaultUserLabel` |
| `SessionModel(identifier: 'abc', label: '')` | `'abc'` | `Constants.defaultUserLabel` (empty = absent) |
| `SessionModel(identifier: '', ...)` | `fallbackOwnId` | per label rule |

Guarantees:
- Pure & deterministic — same input → same output; no reads of storage/clock.
- `id` and `label` are always non-empty.
- The rule is defined **once**; the thread bloc and the message repository both call it (no divergent `?? 'me'` inline expressions).

## Consumers

- `ChatThreadBloc._onInitialize` — `currentId = resolveIdentity(session).id`; optimistic send `authorLabel = resolveIdentity(session).label`.
- `MessageRepositoryImpl._seedChatIfEmpty` — rewrites seed rows where `authorId == IdentityMockData.fallbackOwnId` to `resolveIdentity(session).id`.
- `MessageRepositoryImpl.sendMessage` — resolves the identity and passes `authorId`/`authorLabel` to `SendMessageApi.execute` (which becomes a dumb echo of the given identity).
