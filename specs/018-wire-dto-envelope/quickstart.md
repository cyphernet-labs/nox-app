# Quickstart & Validation: wire-DTO envelope (S4)

## Automated (the gate)

```bash
make generate        # freezed + json_serializable for the new wire entities; injectable unchanged
make gate            # generate -> format -> analyze -> test (goldens excluded)
make golden-verify   # unchanged — no UI change, no new golden
```

Targeted:

```bash
make test FILE=test/data/entity/chat/wire/chat_wire_entity_test.dart        # round-trip + converter
make test FILE=test/data/entity/chat/wire/message_wire_entity_test.dart     # round-trip (nested attachment)
make test FILE=test/data/mapper/chat/chat_wire_mapper_test.dart             # wire<->model loss-free
make test FILE=test/data/mapper/chat/message_wire_mapper_test.dart          # wire<->model (attachment/system)
make test FILE=test/data/repository/chat/chat_repository_impl_test.dart     # unwrap + error/empty envelope
make test FILE=test/data/repository/chat/message_repository_impl_test.dart  # unwrap + error/empty envelope
```

## Behavior-preservation check (SC-001)

The FULL existing suite passes with ZERO edits: chat/message repo tests, ChatsListBloc / ChatThreadBloc
tests, and all page/golden tests. If any existing test needs editing, behavior drifted — investigate.

## Success-criteria mapping

| Criterion | Validated by |
|-----------|--------------|
| SC-001 (no behavior change) | full existing suite unchanged |
| SC-002 (round-trip every registered type) | entity round-trip tests + converter test |
| SC-003 (repo unwrap; empty/error → error) | repo tests (success + null-data + success:false) |
| SC-004 (0 un-enveloped boundaries) | grep: chat/message data sources return ResponseEntity<wire> |
| SC-005 (0 UI change) | make gate + make golden-verify green, no golden delta |
| SC-006 (localized flip-to-backend) | contracts/wire-envelope.md + di-binding unchanged |

## Rollback

Reverting the branch restores the direct-domain-model boundary. No schema, no persisted change, no user-facing effect either way.
