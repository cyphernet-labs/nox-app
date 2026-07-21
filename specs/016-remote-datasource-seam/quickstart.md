# Quickstart & Validation: Remote-Data-Source Seam

A pure structural refactor — the proof is "everything still works, and the boundary is now swappable."

## Prerequisites

- `make generate` (the new `@LazySingleton(as:)` bindings + repo constructor changes regenerate `configure_dependencies.config.dart`).

## Automated validation (the gate)

```bash
make gate            # generate → format → analyze → test (goldens excluded)
make golden-verify   # unchanged — no new goldens (behaviour identical)
```

Targeted:

```bash
make test FILE=test/data/remote/datasource/seam_binding_test.dart        # the rebinding proof (SC-002)
make test FILE=test/data/repository/chat/message_repository_impl_test.dart
make test FILE=test/data/repository/item/item_repository_impl_test.dart
make test FILE=test/data/remote/api                                       # generators — must be UNCHANGED & green
```

## What to verify

| Check | How | Criterion |
|-------|-----|-----------|
| Repos depend on interfaces | grep repositories for `GetChatsApi`/`GetMessagesApi`/`SendMessageApi`/`GetChatFilesApi`/`GetItemsApi` | 0 hits (SC-001) |
| Mocks reachable only as impls | grep repos for `MockChatRemoteDataSource` etc. | 0 hits (repos see the interface only) |
| One seam per feature | `datasource/` has 4 interfaces | count == features with a network boundary (SC-005) |
| Behaviour unchanged | full suite + goldens | all green, no behavioural assertion edits (SC-003) |
| App still boots on mocks | per-platform compile-smoke / `flutter run -d macos --dart-define-from-file=config/stage.json` | mocks resolve, no real call (SC-004) |
| Swappable | `seam_binding_test` | a rebound interface routes the repo to it (SC-002) |

## The flip recipe (for the future backend task — ≤3 steps per feature)

1. Add `RealChatRemoteDataSource implements ChatRemoteDataSource` (real HTTP) `@LazySingleton(as: ChatRemoteDataSource, env: [Environment.prod])`.
2. Change `MockChatRemoteDataSource`'s env to `[Environment.dev, Environment.test]`.
3. `make generate`.

Nothing else changes — repository, cache/DAO/mapper, `RepositoryResult`/`PageMetadata`, error mapping, and UI are all untouched. (See `contracts/di-binding.md`.)

## Rollback / safety

- No schema, no behaviour, no UI. Reverting the branch restores the concrete-type injection with no data cleanup.
- The `*Api` mock generators are unchanged, so their deterministic data + timing (and every downstream golden) are identical.
