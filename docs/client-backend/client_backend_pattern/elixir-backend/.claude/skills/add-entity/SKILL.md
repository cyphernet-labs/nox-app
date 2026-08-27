---
name: add-entity
description: Adding a new persisted entity or any new write path to this backend (new resource, new table with CRUD, new mutation on an existing table, new REST endpoints that change data). Use this skill whenever the task adds or modifies functionality that writes to the database or emits events — even for a single new endpoint — so the Writer + transactional-outbox pattern is copied exactly, not approximated.
---

# Adding an entity / write path

Every entity follows the `Backend.Notes` pattern exactly. Copy the
shape; do not invent a variant.

## Steps

1. **Migration** — new STRICT table via the `migrations` skill.
2. **Context module** `lib/backend/<entities>.ex`:
   - reads: `DB.with_read(fn conn -> DB.query(conn, "...", params) end)`;
   - each write: ONE `Writer.transaction(fn conn -> ... end)` whose
     function (a) mutates with `RETURNING` to capture the final row,
     (b) calls a private `insert_event(conn, "<entity>.<verb>", id,
     payload)` copied from Notes, and returns `{row, event}`;
   - broadcast: only in the `{:ok, {row, event}}` branch AFTER the
     transaction returns, via the `push_event/1` seam — never inside
     the transaction function;
   - not-found: empty `RETURNING` result → `{:error, :not_found}`;
   - validation before the transaction (`with :ok <- validate(...)`),
     mirroring the SQL CHECK bounds.
3. **Web layer**: routes in `router.ex` under the `:api` pipeline;
   controller translating context results to statuses exactly as
   `NoteController` does (400 invalid / 404 not_found / 500 other);
   no logic in controllers.
4. **Events contract**: payload is the full entity map; exception:
   `<entity>.deleted` carries `%{"id" => id}`. `entity` column = entity
   name. Document new event types in README's WebSocket section.
5. **Tests**: fresh temp db, real context, assert (a) the mutation,
   (b) exactly one `events` row with correct type/seq,
   (c) `events_since/1` returns it decoded.

## Anti-patterns (each violates a CLAUDE.md invariant)

- Opening a write connection outside the Writer, or mutating SQL through
  `DB.with_read` → invariant 2.
- Broadcasting inside the transaction function, or mutating without an
  event → invariant 4.
- Slow work (network, sleep, heavy computation) inside
  `Writer.transaction/1` — it stalls every write on the node
  → invariant 3.
- Reaching for Ecto/changesets "just for validation" → style rules;
  validation is plain functions plus SQL CHECKs.
- Re-reading after commit instead of `RETURNING` inside the transaction.

## New realtime topic (only if the entity needs its own channel)

Default: reuse `events:all` — clients filter by `entity`. A dedicated
topic needs: a `channel "<name>:*"` route in `UserSocket`, a channel
module copying `EventsChannel`'s join + `{:replay, last_seq}` order
exactly, and broadcasts to the new topic from the context. Preserve
CLAUDE.md invariant 5 verbatim.
