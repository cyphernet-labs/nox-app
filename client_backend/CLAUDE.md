# CLAUDE.md — NOX client server (Go)

Self-hosted messenger backend for a circle of ~10 users: one WebSocket
command channel (JSON envelope, global `seq` event log, cursor replay)
plus a small REST surface (file upload/download, /health), embedded
SQLite, single static CGO-free binary.

**The contract is law:** `docs/client-backend/protocol/contract-draft.md`
(v0). Every command, event, field name, error code and rule comes from
there; a change needed on the wire is first a contract edit, then code.

**Stage 2 is under way (feature 032).** The server now CHECKS who connects:
`device_key` is an Ed25519 public key, `signature` over
`"nox/challenge/v1:" ‖ challenge` is verified on every greeting, and the
person is found by that key. `login_ref` is gone from the wire, the lookup
and the schema — presenting a secret was replaced by proving possession of
a key that never leaves the device. A greeting can no longer create anyone:
an unknown key is refused (`unauthenticated`), and people come into being
only through `pair` (§8A). Still out of scope and blocked: `recover` and the
recovery phrase (Q16), inviting a new PERSON rather than a device (Q15),
TLS with pinning.

Architecture rationale lives in `docs/blueprints/client-backend/README.md`;
Go style rules live in the `go-style` skill; WebSocket/REST runtime
machinery — in the `ws-rest-patterns` skill. Read them before writing
code. Reference prototypes (same seq/outbox/replay architecture, simpler
protocol): `docs/client-backend/client_backend_pattern/go-backend/`.

## Commands

    go mod tidy               # after any dependency change (rare)
    gofmt -l .                # must print nothing
    go vet ./...
    go test -race ./...       # -race is mandatory, not optional
    go build -o noxd . && ./noxd -addr 127.0.0.1:8080 -db nox.db

## Toolchain & dependencies

- Go **1.27**. Direct dependencies: exactly three — `github.com/coder/websocket`,
  `modernc.org/sqlite`, `golang.org/x/sync` (errgroup). Adding any other
  requires written justification; "convenient" is not one.
- `modernc.org/libc` does not follow semver — its version stays pinned;
  bump only together with `modernc.org/sqlite` and run the full test suite.
- Dev tools go through `tool` directives in go.mod (Go 1.24+), never a
  `tools.go` with blank imports.

## Architecture invariants (MUST hold after every change)

1. **Exactly one OS process opens the database file.** No sidecars, no
   cron, no second node.
2. **Two pools, one writer.** All writes go through `internal/store`
   using the write handle (`SetMaxOpenConns(1)` + `_txlock=immediate`);
   reads use the read pool. Never `Exec` a mutation on the read handle;
   never add a second write handle; never write outside `internal/store`.
3. **Transactional outbox.** Every mutation visible on the wire as an
   event inserts its `events` row in the SAME transaction; broadcasting
   happens only AFTER `Commit` returns (via the dispatcher). Never
   broadcast inside a transaction. Two lifecycles are deliberately
   event-less: file metadata (upload registration, mark-uploaded, orphan
   sweep), because files surface to other clients only through
   `message.send`; and identity resolution (`internal/store/identity.go`),
   because a person or a device coming into being is not visible on the
   wire at all.
4. **Write transactions are milliseconds.** No network I/O, no WebSocket
   sends, no sleeping between `BeginTx` and `Commit`.
5. **`seq` is a strictly increasing total order** (single writer +
   AUTOINCREMENT), global across the database — never per-chat. Never
   renumber or bulk-delete events in a way that breaks `since` replay.
6. **WebSocket ordering: subscribe → replay → live** per contract §3.
   Duplicates at the boundary are expected (clients de-duplicate by
   `seq`); loss is not. The client is caught up when it has processed
   `seq >= cursor` from the hello reply.
7. **The hub owns the subscriber set.** Interaction only via its
   channels (register/unregister/broadcast). This program contains no
   mutex; if a change seems to need one, restructure so one goroutine
   owns the state.
8. **One reader goroutine per connection** (library invariant); writes
   to a client go through its buffered channel (~16 frames); overflow →
   `Close(StatusPolicyViolation)` — replay heals the client on
   reconnect. Keepalive: own ticker with `Ping(ctx)` ~25s.
   `SetReadLimit(max_frame_bytes)`.
9. **Shutdown order:** HTTP server drains → registered WS conns get
   `Close(StatusGoingAway)` (Shutdown does NOT wait for hijacked conns —
   keep the conn registry wired via `RegisterOnShutdown`) → hub stops →
   DB closes. Preserve it.
10. **Idempotency:** `message.send` is keyed by `(author_id,
    client_message_id)`; a replayed command returns the original echo,
    never a duplicate row. Per person, so two people colliding on a send
    key do not collide with each other.
11. **Envelope discipline (contract §2):** four frame kinds only
    (`srv`/`cmd`/`ok`+`error`/`event`); unknown fields in incoming
    frames are ignored (v0 evolves); unknown commands answer
    `invalid_request`. Error codes only from contract §2.1.
12. **Migrations are append-only** numbered `.sql` in `migrations/`,
    embedded via `embed.FS`, applied by `PRAGMA user_version` at startup
    before endpoints open. Never edit an applied file — see the
    `migrations` skill. **Pre-release exception (owner, 2026-08-27):**
    until the first release the whole schema lives in the single
    `001_init.sql` and schema changes edit it in place — no deployed
    databases exist yet. Append-only numbering starts with the first
    release.
13. **Pragmas are fixed** in `internal/db` (busy_timeout(5000) first,
    then WAL, synchronous(NORMAL), foreign_keys(1)) for every
    connection. Do not vary per-call.

## Code style (details in the go-style skill)

- Standard library first; raw parameterized SQL (`?`); no ORM, no query
  builder, no string-built SQL ever.
- Errors: wrap with `fmt.Errorf("...: %w", err)`; `errors.Is/As`; no
  `panic` in the request path; `os.Exit`/`log.Fatal` only in `main`.
- `context.Context` is the first parameter of anything that blocks.
- No `init()`, no package-level mutable state outside `main` wiring.
- Package names: one word, lowercase, describe contents; no
  `util`/`common`/`helpers`.
- Logging: `slog` only, structured; no `fmt.Print*` outside `main`.
- `gofmt` formatting; compile clean under `go vet`.

## File map

- `main.go`              — flags, wiring, ordered startup/shutdown (~3 lines of logic)
- `internal/config/`     — flags + `NOX_*` env, validated at start
- `internal/db/`         — pools, pragmas, `user_version` migration runner
- `internal/store/`      — types + all reads/writes; the ONLY writer code
- `internal/store/identity.go` — identity resolution: the person is found by
  the device's public key, and an unknown key is refused rather than enrolled;
  the second event-less write besides file metadata
- `internal/store/serverkey.go` — the machine's own key pair and the ownership
  state machine (`claimed_at IS NULL` means only claim tokens are accepted)
- `internal/store/pairing.go` — one-shot tokens and `Pair`; burning is a
  conditional UPDATE whose affected-row count settles a two-device race
- `internal/store/devices.go` — device list, revocation (DELETE, so a revoked
  device is indistinguishable from an unknown one), rename
- `internal/hub/`        — fan-out goroutine owning the subscriber set
- `internal/protocol/`   — envelope v0 types, error codes, frame (un)marshal
- `internal/server/`     — ServeMux wiring: `/ws`, REST (§1 of contract), middleware
- `migrations/`          — append-only numbered `.sql` (embedded)

## Testing

- Table tests; each test opens its own DB file in `t.TempDir()` and
  migrates from zero. **Never `:memory:` with `database/sql`** — each
  pooled connection gets a private database.
- HTTP via `httptest` against the real mux; WS via `httptest.NewServer`
  + `websocket.Dial(ctx, srv.URL, nil)`.
- Concurrency/replay tests may use `testing/synctest` (GA since 1.25).
- Always `go test -race ./...`.

## Operational constraints

- Bind loopback in dev; TLS/pinning arrives with the pairing work — do
  not add certificate code casually.
- Backups: `VACUUM INTO` a temp file + rename; never copy a live DB;
  local filesystem only (WAL breaks on network mounts).
- Build: `CGO_ENABLED=0 go build -trimpath -ldflags="-s"`.

## Known deliberate omissions (do not "fix" silently)

- The claim token has NO expiry. It dies by being used, only someone with
  access to the machine ever sees it, and an expiring one would leave an
  installed-then-forgotten server unclaimable with no way to mint another.
  Device invites do expire, after ten minutes.
- The server's private key lives INSIDE the database file. The model's case 6
  warns that a backup holding only the DB breaks pinning for every device at
  once; one artifact makes that impossible, and anyone who can read the file
  already has every message.
- The claim link is printed to the log and nowhere else. A local HTTP page
  serving the QR would hand ownership to everyone on the network while the
  transport is not TLS.
- The CLAIM link falls back to loopback under a wildcard bind (it is read on the
  machine), while an INVITE link uses the address the requesting device dialled
  (its `Host` header). The two differ because an invite is carried to another
  device, and loopback there is a link nothing can dial.
- `users.label` is neither unique nor validated (owner, 2026-09-02): a
  greeting may never be refused because of a name, since the client
  retries a refused greeting forever.
- No push, no `chat.markRead`, message `body` is open text — all gated
  by open questions; see contract §8 before touching.
- Cyrillic never appears in code, comments, or commit messages.
