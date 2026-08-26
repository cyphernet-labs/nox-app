# CLAUDE.md — personal-backend (Go)

Personal server: REST JSON API + push-only WebSocket, embedded SQLite,
single static binary, no external services. Low load by design (~tens of
clients). Read this file fully before changing code; the invariants below
are the architecture — violating one is a bug even if tests pass.

## Commands

    go mod tidy          # after any dependency change (rare; see style)
    gofmt -l .           # must print nothing
    go vet ./...
    go test -race ./...  # -race is mandatory, not optional
    go build -o server . && ./server -addr 127.0.0.1:8080 -db app.db

## Architecture invariants (MUST hold after every change)

1. **Exactly one OS process opens the database file.** Never spawn a
   second process, sidecar, or cron job that touches `app.db`.
2. **Single writer, structurally.** All writes go through `Store` methods
   using the `write` handle (`MaxOpenConns(1)` + `_txlock=immediate`).
   Never `Exec` a mutation on the `read` handle; never add a second write
   handle; never write from a goroutine outside `store.go`.
3. **Transactional outbox.** Every mutation and its `events` row are
   inserted in the SAME `BEGIN IMMEDIATE` transaction. `hub.Broadcast`
   runs only AFTER `Commit` returns. Never broadcast inside a
   transaction; never mutate without an event.
4. **Write transactions are milliseconds.** No network I/O, no WebSocket
   sends, no sleeping, no long computation between `BeginTx` and
   `Commit`.
5. **The hub owns the subscriber set.** Interaction only via its three
   channels (`register/unregister/broadcast`). This program contains no
   mutex; if a change seems to need one, restructure so one goroutine
   owns the state instead.
6. **WebSocket ordering: subscribe → replay → live.** In `ws.go` the hub
   subscription happens before the replay query. Duplicates at the
   boundary are expected; loss is not. Clients de-duplicate by `seq`.
7. **`seq` is a strictly increasing total order** (single writer +
   `AUTOINCREMENT`). Never reuse, renumber, or bulk-delete events in a
   way that breaks `?since=N` replay for connected clients.
8. **Pragmas are fixed**: WAL, busy_timeout=5000, synchronous=NORMAL,
   foreign_keys=ON, set in `db.go` for every connection. Do not vary
   them per-call.
9. **Migrations are append-only** numbered files applied by
   `PRAGMA user_version`. Never edit an already-applied file — see the
   `migrations` skill before any schema change.
10. **Shutdown order**: HTTP server drains first, hub stops second
    (`main.go`). Preserve it; reversing deadlocks handlers on
    `Unsubscribe`.

## Code style

- Standard library first. Current third-party dependencies: exactly two
  (`modernc.org/sqlite`, `github.com/coder/websocket`). Adding any
  dependency requires explicit justification; "convenient" is not one.
- Raw parameterized SQL with `?` placeholders. No ORM, no query builder,
  no string-formatted SQL ever. The SQL on the page is the audited
  artifact.
- Explicit error handling: return wrapped errors (`fmt.Errorf("...: %w",
  err)`); no `panic` in the request path; no swallowed errors.
- Single `package main`, one file per responsibility (see map). Keep
  handlers thin: parse/validate in `api.go`, logic in `store.go`.
- `gofmt` formatting; no exceptions.

## File map

- `main.go`      — flags, wiring, ordered startup/shutdown
- `db.go`        — connection handles, pragmas, migration runner
- `migrations/`  — append-only numbered `.sql` (embedded in the binary)
- `store.go`     — types + all reads/writes; the ONLY writer code
- `hub.go`       — fan-out goroutine owning the subscriber set
- `ws.go`        — `/ws` handler: subscribe, replay, stream, ping
- `api.go`       — REST handlers, JSON helpers, validation

## Testing

- Each test opens its own temp-file database (`t.TempDir()`), runs
  `migrate`, and exercises the real `Store`. Never `:memory:` with
  `database/sql` — each pooled connection gets a private database.
- HTTP via `httptest` against `addRoutes`. Always `go test -race`.

## Operational constraints

- Bind loopback only; Caddy terminates TLS in front. Do not add TLS or
  certificate code to this binary.
- Backups: `VACUUM INTO` shipped off-machine, or Litestream. Never copy
  a live db file. Local filesystem only (WAL breaks on network mounts).

## Known deliberate omissions (do not "fix" silently)

- No authentication yet: the intended shape is bearer-token middleware in
  `api.go` plus a token check in `ws.go` before `Accept`. Ask before
  implementing differently.
- `OriginPatterns: ["*"]` in `ws.go` is a development setting; restrict
  before exposure.
- No outbox pruning; adding it requires a client-sync policy first (see
  the `event-protocol` skill).
