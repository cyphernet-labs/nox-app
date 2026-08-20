---
name: add-entity
description: Adding a new persisted entity or any new write path to this backend (new resource, new table with CRUD, new mutation on an existing table, new REST endpoints that change data). Use this skill whenever the task adds or modifies functionality that writes to the database or emits events — even for a single new endpoint — so the single-writer + transactional-outbox pattern is copied exactly, not approximated.
---

# Adding an entity / write path

Every entity follows the `Note` pattern exactly. Copy the shape; do not
invent a variant.

## Steps

1. **Migration** — new STRICT table via the `migrations` skill.
2. **Types + store** (`store.go`):
   - struct with JSON tags;
   - reads on `s.read` (`QueryContext`/`QueryRowContext`, `?` params);
   - each write is ONE `s.inTx(...)` call that (a) mutates using
     `RETURNING` to capture the final row, (b) calls `insertEvent` with
     type `"<entity>.<verb>"`, and returns; the caller then
     `s.hub.Broadcast(ev)` — after commit, never inside;
   - not-found: `RETURNING` scan gives `sql.ErrNoRows` → return
     `ErrNotFound`.
3. **REST** (`api.go`): input struct with a `validate()` method
   (trim, length bounds mirroring the SQL CHECKs), handlers wired in
   `addRoutes` with Go 1.22 method patterns
   (`"POST /api/<entities>"`, `"GET /api/<entities>/{id}"`), responses
   via `writeJSON`, errors via `badRequest`/`notFoundOr500`.
4. **Events contract**: payload is the full serialized entity;
   exception: `<entity>.deleted` carries `{"id": N}`. The `entity`
   column gets the entity name. Document new event types in README's
   WebSocket section.
5. **Tests**: temp-file db, real `Store`, assert (a) the mutation,
   (b) that exactly one `events` row with the right type/seq exists,
   (c) `EventsSince` returns it. Run `go test -race ./...`.

## Anti-patterns (each violates a CLAUDE.md invariant)

- Writing through `s.read`, `database/sql` directly, or a new handle
  → invariant 2.
- Broadcasting inside the transaction, or mutating without an event
  → invariant 3.
- Doing network I/O / long work inside `inTx` → invariant 4.
- Adding a mutex or writing to hub internals → invariant 5.
- Skipping `RETURNING` and re-reading after commit (races with other
  writes' event ordering; `RETURNING` inside the tx is the source of
  truth).

## When the entity needs list filtering/pagination

Add explicit SQL (`WHERE`, `LIMIT ?/OFFSET ?`) with validated numeric
bounds in the handler. Do not add a query-builder dependency.
