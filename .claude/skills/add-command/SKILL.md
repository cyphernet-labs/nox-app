---
name: add-command
description: Add or change a command/event of the WebSocket envelope in client_backend — the checklist that keeps code, contract and tests in lockstep. Use for any new cmd handler, new event type, or a change to an existing frame's fields.
user-invocable: true
---

# Add a command or event

The wire is contract-first: `docs/client-backend/protocol/contract-draft.md` is the
single source of truth. Code never invents a field.

## Order of work

1. **Contract check.** Find the command/event in the contract. If it is not there or
   differs from what is being asked: STOP and update the contract first (a stage-2 /
   blocked §8 item must not be implemented at all — say so instead). Field names,
   error codes and semantics come from the contract verbatim.
2. **Protocol types** (`internal/protocol/`): request/response `data` structs with
   json tags exactly matching the contract; register the `cmd` name in the dispatch
   table. Unknown incoming fields are ignored by design — do not add
   DisallowUnknownFields here (contract tests only).
3. **Store** (`internal/store/`): one method per operation; reads on the read pool,
   mutations on the write handle inside ONE transaction that also inserts the
   `events` row (invariants 2–4). Return `(T, error)`; map SQL absence to the
   store's not-found error, not to nil.
4. **Handler** (`internal/server/`): decode → validate (limits, field rules from the
   contract — e.g. name trim/length, body-or-attachment) → store call → reply frame.
   Validation failures answer the exact contract error code (`invalid_request`,
   `name_taken`, `payload_too_large`…). Handlers stay thin: no SQL, no business
   rules beyond validation.
5. **Event fan-out:** if the mutation emits an event, the store already wrote the
   event row; after Commit the caller passes it to `hub.Broadcast`. The event `data`
   is the FULL wire model (contract §6), never just an id.
6. **Idempotency:** commands with a client key (`message.send` / `client_message_id`)
   must return the original result on replay — UNIQUE constraint + select-on-conflict,
   not read-then-write.
7. **Tests** (colocated `_test.go`):
   - table test on the handler through a real mux + real temp-DB store;
   - the error paths for every contract error code the command can return;
   - for events: subscribe via WS dial, run the command, assert the event frame and
     its `seq` monotonicity;
   - replay test: command → reconnect with `since` → the event arrives again and is
     deduplicated by `seq`.
8. **Docs:** if implementing revealed a contract gap or ambiguity — update
   `contract-draft.md` in the same change-set and say so in the commit message.

## Frame shapes (memorize)

```json
{"id": 7, "cmd": "chat.create", "data": {...}}
{"id": 7, "ok": true, "data": {...}}
{"id": 7, "ok": false, "error": {"code": "name_taken", "message": "..."}}
{"seq": 1042, "event": "message.new", "data": {...}}
```

`id` — client-issued, per-connection; `seq` — server-issued, global total order.
A handler must always answer exactly once per `id`, even on failure.

## Definition of done

gofmt clean · go vet clean · `go test -race ./...` green · contract and code agree
field-by-field · CLAUDE.md invariants untouched or consciously amended in the same
change-set.
