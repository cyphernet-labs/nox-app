# CLAUDE.md — NOX client server (Go)

Self-hosted messenger backend for ONE person and the devices they own:
one WebSocket command channel (JSON envelope, global `seq` event log,
cursor replay) plus a small REST surface (file upload/download), both behind
the channel check of feature 044, embedded SQLite, single static CGO-free
binary. tor, when the machine has one, is a separate OS service run by the
owner or the install script (049): it publishes the onion service and
forwards it to the main port. The server spawns no process, holds none of
tor's keys and only stores its own addresses - the public one and the onion
one (045). Different people never share a machine and their machines never
talk to each other — everything between people goes through a relay whose
protocol does not exist yet (Q13).

**The contract is law:** `docs/client-backend/protocol/contract-draft.md`
(v0). Every command, event, field name, error code and rule comes from
there; a change needed on the wire is first a contract edit, then code.

**Who connects is decided by the channel (feature 044).** Every connection -
the WebSocket and every file transfer alike - is TCP (straight from the
device, or from the tor service forwarding the onion service), then TLS 1.3
on a THROWAWAY certificate the server mints in memory at every start and
nobody checks, then the Eidolon exchange over the TLS 1.3 exporter
(RFC 9266, `internal/eidolon`): the device sends its Ed25519 key with a
signature over the key and one over the binding, the server checks both and
answers with the machine's own Ed25519 key the same way. Only then does
`http.Server` see the connection, carrying the device key it proved
(`channelPeer`). The server accepts ANY key that proves itself and grants
rights by the store: a paired device gets everything, an unknown key only
`pair` - within two minutes, on one of at most 32 such connections
(`unpaired.go`); `session.hello` with an unknown key is `unauthenticated`
(the device reads it as a revocation), and `/files` refuses an unpaired key
with `401` before it looks at the token. Off `/ws` an unknown key gets one
request per connection: the door in front of the mux (`limitStrangers`)
ends the connection with every answer but a WebSocket upgrade. The greeting
has no challenge, `session.hello` and `pair` carry no device key, and the
pairing link is `nox://pair/` version 3 (contract §8A). People come into
being only through `pair`; the
machine belongs to ONE person (037) and `owner_user_id` survives only as the
"this machine has been claimed" marker. Still out of scope and blocked:
`recover` and the recovery phrase (Q16), the protocol to the relay (Q13), and
ATS / App Review for a personal server reached through the app's own Rust
module (Q14, due before release).

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

- Go **1.27**. Direct dependencies: exactly four — `github.com/coder/websocket`,
  `modernc.org/sqlite`, `golang.org/x/sync` (errgroup) and `rsc.io/qr`. Adding
  any other requires written justification; "convenient" is not one.
- **Why `rsc.io/qr` (035):** encoding a QR is a whole capability — Reed-Solomon
  over GF(256), version selection, eight masks scored by penalty — not a
  convenience, and writing it here buys nothing but our own bugs in the thing
  people scan to take ownership of a server. Pure Go, no dependencies of its
  own, no CGO, so `CGO_ENABLED=0` static builds are untouched.
- `modernc.org/libc` does not follow semver — its version stays pinned;
  bump only together with `modernc.org/sqlite` and run the full test suite.
- Dev tools go through `tool` directives in go.mod (Go 1.24+), never a
  `tools.go` with blank imports.

## Architecture invariants (MUST hold after every change)

1. **Exactly one OS process opens the database file, and the server spawns
   NO process at all.** No sidecars that touch the database, no cron, no
   second node, no child process of any kind. tor is a separate OS service
   (045): it never opens the database, the server never starts, commands or
   stops it, and all the server knows of it is the onion address stored in
   `server_identity`. `run_test.go` holds that `Run` starts no tor even with
   one on the PATH.
2. **Two pools, one writer.** All writes go through `internal/store`
   using the write handle (`SetMaxOpenConns(1)` + `_txlock=immediate`);
   reads use the read pool. Never `Exec` a mutation on the read handle;
   never add a second write handle; never write outside `internal/store`.
3. **Transactional outbox.** Every mutation visible on the wire as an
   event inserts its `events` row in the SAME transaction; broadcasting
   happens only AFTER `Commit` returns (via the dispatcher). Never
   broadcast inside a transaction. Two lifecycles are deliberately
   event-less: file metadata (upload registration, continuation,
   mark-uploaded, orphan sweep), because files surface to other clients
   only through `message.send`; and identity resolution (`internal/store/identity.go`),
   because a PERSON coming into being is not visible on the wire at all.
   The rule is about the JOURNAL, and the three off-journal events sit outside
   it by construction: `device.revoked`, `identity.updated` and - since 038 -
   `device.paired` carry `seq: 0`, write no `events` row, take no cursor
   coordinate and are never replayed. They describe who a connection is or what
   it may still do, not what happened in the shared world, which is why a
   disconnect may lose them and nothing breaks.
   `server.addresses` (039) is the fourth: it says where this machine can be
   reached - the addresses found on its networks plus the stored public and
   onion address (045) - has ONE sender, the address watcher, and the
   greeting reply is its reliable half. A `Set` on the service page only
   writes the store and pokes the watcher; it never sends the event itself.
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
   channels (register/unregister/broadcast) - the hub itself holds no
   mutex, and a change that seems to need one there means restructuring
   so one goroutine owns the state. The connection REGISTRY is the
   deliberate exception: `Server.mu` guards `conns` and the per-connection
   fields other connections read (identity), because the fan-out helpers
   walk one person's connections from another's goroutine. It guards
   `transfers` too - the `/files` requests under way, each registered under
   the key its connection proved - because a revocation on one connection
   cuts another device's transfers, which since 044 run on connections of
   their own. It guards `unpaired` as well - the /ws connections of keys
   nobody paired, oldest first, each holding its own place in the list
   (`unpaired.go`) - because a newcomer's handler takes the oldest of them
   out to make room, and each one's deadline fires on a timer's goroutine.
   The device key needs no lock: the channel fixes it before the
   connection is registered, and it never changes.
   `Server.claim`, the transfer-token store (`internal/server/tokens.go`),
   the upload-writer registry (043, `internal/server/writers.go`: which
   request is writing which part, so a new PUT can interrupt one whose
   connection died silently instead of writing beside it) and each channel
   listener's registry of handshakes under way (`internal/server/channel.go`:
   which connections are still proving a key, oldest first and counted per
   source - this machine being one source with a share of its own - so the
   accept loop can cut the oldest - of one source, or of all - without ever
   waiting) hold the only other four. The mutex inside each PUT's
   `stallReader` (`files.go`) is NOT a fifth: it lives and dies with one
   request, guards nothing another request or connection reads, and only
   orders that request's read-deadline renewal against an interrupt, so the
   interrupt is never pushed back by a whole stall timeout. Since 039 the
   connection registry also carries `greeted`
   and `addrVersion` per connection, set under `Server.mu` AFTER the greeting
   reply is queued - which is what keeps `server.addresses` behind it. The
   address snapshot (`addressSet`: the found addresses plus the stored public
   and onion address) reaches readers behind `atomic.Pointer`, not under a
   lock; there is no Tor state in the process.
8. **One reader goroutine per connection** (library invariant); writes
   to a client go through its buffered channel (`outBuffer` = 64 frames); overflow →
   `Close(StatusPolicyViolation)` — replay heals the client on
   reconnect. Keepalive: own ticker with `Ping(ctx)` ~25s, on a goroutine
   BESIDE the writer - Ping waits a whole round trip, which over Tor is
   seconds, and a writer parked on it lets live frames overflow the queue.
   `SetReadLimit(max_frame_bytes)`.
9. **Shutdown order:** the HTTP servers drain (main, then the status page,
   each on its OWN deadline) → registered WS conns get
   `Close(StatusGoingAway)`, IN PARALLEL - one close handshake can take 10 s,
   and over Tor it does (Shutdown does NOT wait for hijacked conns — keep the
   conn registry wired via `RegisterOnShutdown`) → wait for the handlers, up
   to 15 s → the address watcher stops (on its OWN context, so it still
   reaches the connections being told goodbye) → hub stops → DB closes.
   Preserve it. There is no tor to stop: it is not the server's process.
10. **Idempotency:** `message.send` is keyed by `(author_id,
    client_message_id)`; a replayed command returns the original echo,
    never a duplicate row. The key keeps `author_id` because that is the
    column the message write path and its index are built on — not to keep
    two people from colliding, since there is only one. `chat.create` with
    a device-minted `chat_id` (`^c_[0-9a-f]{32}$`, 041) is idempotent by
    that id: the id is looked up BEFORE the name inside the one write
    transaction, and a repeat returns the chat as it is now, writing no row
    and no event — checking the name first would answer `name_taken` to a
    create that succeeded.
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
- `internal/store/serverkey.go` — the machine's own key pair AND its owner:
  `owner_user_id` on the single `server_identity` row is the ownership state
  machine, and `claimed_at` is only a timestamp nothing decides by
- `internal/store/pairing.go` — one-shot tokens and `Pair`; burning is a
  conditional UPDATE whose affected-row count settles a two-device race
- `internal/store/devices.go` — device list, revocation (DELETE, so a revoked
  device is indistinguishable from an unknown one), rename
- `internal/store/addresses.go` — the two stored addresses (045):
  `public_address` and `onion_address` on the single `server_identity` row,
  each with the start parameter it was last written from (`*_address_param`);
  a parameter is applied together with its value in ONE statement. The store
  checks nothing - the server does, before it writes
- `internal/server/addresses.go` — where this machine can be reached: the
  versioned snapshot (the addresses found on its networks plus the stored
  public and onion address) and the watcher that is the only sender of
  `server.addresses`
- `internal/server/address_settings.go` — the checks both roads to the stored
  addresses go through (045): a v3 onion address (base32, SHA3-256 checksum,
  version byte) and a public `host:port`; the start parameters
  `-public-addr`/`-onion-addr`, applied when they appeared or changed and
  turned into page warnings when malformed; `onionHost`, the one sign left
  that a request came through tor
- `internal/server/logscrub.go` — the ONE slog handler every line of the
  process goes through (`ScrubLogs`: main wraps the process handler, `Run` and
  `New` wrap whatever logger they get, net/http's error log is routed through
  it): onion addresses become `[onion]` and pairing links `[link]`, whatever
  the text came from - a call site covers only the text its author thought of
- `internal/server/status_page.go` — the service page's own mux on its
  loopback listener: the claim link and QR, the address forms (`POST
  /addresses` checks `Host`, `Origin` and the per-process form token; CSP
  `form-action 'self'`) and `GET /health`
- `internal/hub/`        — fan-out goroutine owning the subscriber set
- `internal/protocol/`   — envelope v0 types, error codes, frame (un)marshal
- `internal/server/`     — ServeMux wiring: `/ws`, REST (§1 of contract), middleware
- `internal/eidolon/`   — the channel check (044): the 160-byte message, the
  responder the server runs and the initiator `cmd/smoke` and the tests run;
  shared vectors with the app's Rust module in `testdata/vectors.json`
- `internal/server/channel.go` — the front door: a listener wrapper that takes
  every connection through TLS and the check on a goroutine of its own, under
  ONE deadline from accept - 30 s, the slow-path budget, for every connection,
  since one from the tor service arrives on this same port and looks like any
  other (045) - and hands `http.Server` only the ones that passed, with the
  proved connection - and its key - in the request context. Its accept loop
  never waits and never turns a newcomer away: a source (an IPv4 address, an
  IPv6 /64) has at most 8 handshakes under way and its oldest is cut for the
  next from it; THIS MACHINE - loopback, or the very address a connection
  reached, which is where tor connects from when its onion service points at
  the bound address (unforgeable: the SYN-ACK to a forged source goes to the
  server itself) - is one source with a share of 64, held the same way and
  to no first-byte limit, bounded because since 045 anybody who knows the
  onion address arrives from here; a peer from anywhere else gets 5 s to
  send its first byte; and past 256 in all the oldest handshake is cut for
  the newcomer. The cuts are logged as counts, once a minute at most -
  `evicted_local` is this machine's share
- `internal/server/unpaired.go` — what a key nobody paired may hold (045).
  The door (`limitStrangers`, in front of the mux) looks the key up on every
  request and holds a stranger to one request per connection: whatever the
  answer, it says `Connection: close` (`strangerWriter` sets it again over
  the `Connection: Upgrade` the WebSocket library writes onto its own
  refusals), and a request that declared a body gets a read deadline already
  past (`endWithAnswer`), so net/http waits for that body neither before the
  answer nor after it. A 101 goes on as a session. The door decides only
  whether the connection outlives the request; rights are still decided by
  `admitTransfer` and `handleWS`, whose 401 ends the connection too. On /ws
  the key is looked up AFTER the connection joins the registry (a revocation
  from then on drops it, as for a transfer); a stranger's session is closed
  with 1008 if it has not paired within 2 minutes, and at most 32 are open
  at once - the OLDEST is closed with 1013 for a newcomer, never the
  newcomer. `pair` or `session.hello` succeeding on it settles it; a paired
  device's connection is never held to either limit. The main `http.Server`
  (`configureMain`, shared by `Run` and the test stack) closes a connection
  idle for 2 minutes between requests (only a paired device's is ever
  kept), hands `OPTIONS *` to the handler instead of answering it itself
  past the door, and gives a body nothing of ours reads 30 s past the
  headers (`boundRequestBody`, a ConnState hook): net/http answers an
  unsupported `Expect` before any handler runs and then reads what is left
  of a declared body, with no deadline of its own. A body a handler reads is
  held to the handler's own deadlines, and net/http lifts the deadline itself
  when it reads behind a request with no body left, so no transfer is
  bounded by it
- `internal/server/tls.go` — the technical certificate: a fresh ECDSA P-256 key
  in memory at every start, TLS 1.3 only, ALPN `http/1.1`, no session tickets
- `internal/server/pairing_link.go` — the version 3 link: build and parse, typed
  addresses in the order public → direct → onion (045), shared vectors with the
  app in `testdata/link-vectors.json`
- `internal/server/files.go` — the file chain (contract §7): `file.uploadBegin`
  with its continuation (`file_id` in, `received` out), the PUT that keeps
  whatever arrives and carries the rest of the file from the offset its token
  names, the GET with Range/If-Range; a body is cut by silence alone (043).
  A new upload token revokes the file's earlier ones, so a PUT that turns up
  late cannot cut the part back past what a newer attempt wrote; and the PUT
  reads the row again once it holds the file, so a token issued before the
  file was finished cannot write over it. Every transfer is registered under
  its device key before that key is looked up, and revoking the device cuts
  its connection mid-body (`dropDevice`)
- `internal/server/writers.go` — one request writes a part at a time; a newer
  request for the same file interrupts the old one
- `internal/blob/`       — attachment bytes on disk, confined by `os.Root`:
  `<id>` a finished file, `<id>.part` an upload still coming, `<id>.synced`
  how many leading bytes of the part are on stable storage (043). The record
  is written only after the part is flushed and lowered before a part is cut
  back, so it never vouches for a byte that is not on disk; the schema knows
  nothing of it
- `migrations/`          — append-only numbered `.sql` (embedded)

## Testing

- Table tests; each test opens its own DB file in `t.TempDir()` and
  migrates from zero. **Never `:memory:` with `database/sql`** — each
  pooled connection gets a private database.
- HTTP and WS go through the REAL front door: the test server listens through
  the channel listener, and the test client dials TCP → TLS 1.3 without
  certificate checks → `eidolon.Initiate` with a device key, then speaks HTTP
  or WebSocket over that connection (`dialAs` in `server_test.go`). NOT
  `httptest.NewTLSServer`: a stock TLS server skips the check this server is
  built around.
- Concurrency/replay tests may use `testing/synctest` (GA since 1.25).
- Nothing in the server runs tor, so no test needs one. `run_test.go` holds
  that `Run` starts no process even with a tor on the PATH and that the
  removed tor flags stop the start with a hint; `oneport_test.go` holds the
  one-port rules - every connection gets the slow-path timeouts and the idle
  timeout, a claim or an invite through the onion service is like any other,
  access keys are gone from the wire; `channel_test.go` holds the entry's
  limits, this machine's share among them (a flood from it cuts only its own,
  loopback and the address a connection reached count as one) and a pipe
  listener whose connections report both of their ends; `unpaired_test.go`
  holds a stranger's deadline and cap, and that a stranger's connection ends
  with every answer but an upgrade - a body declared and never sent and
  net/http's own answers included - while a paired device's stays for the
  next request; the addresses are
  `address_settings_test.go`, `status_addresses_test.go` and
  `internal/store/addresses_test.go`; the log
  is `logscrub_test.go` and `log_audit_test.go`, which drives a whole run -
  parameters, `Set`, a claim, an invite, a refused upgrade through the onion
  service - and finds no onion address, link, token or key in it. The path
  through the real Tor network is checked by hand, with tor run as the
  separate service it is.
- Always `go test -race ./...`.

## Operational constraints

- Bind loopback in dev. The listener is TLS 1.3 and the channel check either
  way: there is no flag to serve plaintext or skip the check, and adding one
  would be adding the downgrade the whole design removed. The SERVICE PAGE is
  the deliberate exception and stays plain HTTP on its own loopback listener,
  together with `GET /health`: the main port answers nothing before the check.
- Backups: `VACUUM INTO` a temp file + rename; never copy a live DB;
  local filesystem only (WAL breaks on network mounts).
- Build: `CGO_ENABLED=0 go build -trimpath -ldflags="-s"`.
- **tor is a separate service** (045). The server spawns no process and has
  no tor flags: `-tor`, `-tor-bin` and `-tor-dir` stop the start with a hint.
  tor's own torrc holds the onion service: `SocksPort 0`, a `DataDirectory`
  and a `HiddenServiceDir` of its own (mode 700; the service's key lives
  there and nowhere else - lose it and the address changes),
  `HiddenServicePort 443 127.0.0.1:<port>` with noxd bound to every
  interface or to loopback (a noxd bound to ONE network address does not
  answer on loopback: tor then points at that address, connects from it, and
  the channel counts it as this machine all the same),
  `HiddenServicePoWDefensesEnabled 1`, and `HiddenServiceMaxStreams 16` with
  `HiddenServiceMaxStreamsCloseCircuit 1`: PoW prices introductions, never the
  streams on a circuit already built, so without the cap one circuit opens
  as many connections to the main port as it likes. The app keeps no cap of
  its own under it: one socket and a handful of transfers share a circuit
  (the prefetch fetches one picture at a time, the outbox sends one upload at
  a time, a download runs once per file), and a circuit closed past the cap
  is a reconnect for the socket and a resume for the transfers (043). A cap on
  dart:io's per-host pool would add a failure of its own - Dio counts the wait
  for a free connection into its connect timeout and leaves the request it
  gave up on queued, holding the next free connection with nothing sent - and
  a working one would need a limiter above Dio (specs/045 research R21).
  0.4.9 is the floor;
  Linux distribution packages are often older - use the Tor Project
  repository; the official macOS tor is UNSIGNED and killed at launch
  on Apple Silicon until signed (ad-hoc is enough for dev). The address tor
  writes to `<HiddenServiceDir>/hostname` reaches the server by
  `-onion-addr` or by `Set` on the service page. With no child process
  there is nothing for a service manager to stop in order: a systemd unit
  needs no `KillMode` of its own.
- **Address flags** (045): `-public-addr` / `NOX_PUBLIC_ADDR` (`host:port`)
  and `-onion-addr` / `NOX_ONION_ADDR` (`<56>.onion`, `:443` allowed) write
  an address into the database only when the parameter appeared or changed
  since the value last applied (`*_address_param`), so an address set on the
  service page survives a restart with the old parameter still in the unit.
  A malformed one is not applied and does not stop the start: the server
  keeps the stored address, logs an error and the page names the parameter
  on every start until it is fixed. An empty one changes nothing; only the
  page deletes an address. The variables are read after the flags are
  parsed, never as their defaults: the usage text a mistyped flag prints goes
  to the journal, and a default there would carry the onion address.

## Known deliberate omissions (do not "fix" silently)

- **A file transfer has no time limit, only a stall limit** (043). The body
  deadline is renewed before every read (PUT) and every write (GET), so a
  transfer is cut after 60 s without a byte and never for taking long:
  through Tor 100 MiB take tens of minutes, and any limit on the whole cuts
  exactly the path away from home. The price is known: a connection trickling
  a byte a minute holds a goroutine for as long as it likes. Its holder is one
  of the person's own devices - a token goes only to a greeted connection, and
  the transfer only to a connection that proved a paired key - and revoking
  that device cuts the transfer at once rather than leaving it to run.
- **The durable length of a part is a file beside it (`<id>.synced`), not a
  column.** A column means editing `001`, and every development database -
  the owner's stand included - would have to be recreated and its devices
  paired again; how much of a part is safe on disk is a property of the
  bytes, which `internal/blob` already owns. A crash costs at most the last
  4 MiB of an upload, sent again. A crash - or any failed commit - between
  the rename that makes the part the file and `uploaded = 1` costs nothing:
  a finished `<id>` of the declared size counts as received in full, so the
  continuation answers `received = size` and the empty PUT lands the commit.
  The bytes cannot be there unless every one was flushed before the rename.
  That commit runs on `context.WithoutCancel`: the client may hang up after
  its last byte, and the request's context dies with it.
- **The continuation waits at most a second for the previous writer, and
  never refuses on it.** It runs on the connection's read loop, which also
  reads pongs, and the direct ping gives up after 5 s. A writer that did not
  let go in time leaves a `received` slightly behind; the PUT cuts the part
  back to its token's offset either way. A writer whose last byte is already
  in is not interrupted at all - it finishes - and the continuation reads the
  row again after the wait, so it sees the file it just waited for.
- **The service page lives on its OWN loopback listener** (`-status-addr`), and
  the main mux serves it nowhere. That separation IS the protection: a check on
  RemoteAddr inside a handler is one somebody eventually routes around with a
  header, and the main server is ordinarily bound to every interface. An empty
  address removes the listener rather than the handler, so the port is not held.
- **The service page has exactly ONE script, admitted by its HASH.** It reveals a
  Copy button and puts the claim link on the clipboard - two lines of base64 are
  not something to select by hand. Three things keep it from being a hole, and
  undoing any of them reopens one: the button ships HIDDEN and the script
  reveals it, so a page whose script did not run shows no dead control; the
  policy names `script-src 'sha256-...'` and never `'unsafe-inline'`, so exactly
  those bytes may run; and `default-src 'none'` still forbids `connect-src`, so
  the script can read the link and has nowhere to send it. The hash is DERIVED
  from the script constant on every response rather than written down: a stored
  derivative is a second copy of one fact. A page with no link
  carries no script and its policy admits none.
- **Clipboard access needs a secure context, and this page has one without TLS.**
  `http://127.0.0.1` and `http://localhost` are potentially trustworthy origins;
  measured in a browser, not assumed. The fallback still exists: if the API is
  missing or refuses, the script selects the link so one keystroke finishes it.
- **One claim token per process.** Startup mints it while nobody can get in
  (`announceClaim`) and seeds it into the page (`seedClaimToken`); minting per
  request would leave an unrevocable door behind every browser refresh, because
  a claim token has no expiry.
- **A loopback bind draws no CODE, but still shows the LINK.** Two questions, and
  conflating them cost the page once: "can a phone dial this" decides the QR, and
  nothing decides whether a link exists. The default `-addr` is `127.0.0.1:8080`,
  where a phone cannot reach the server at all - but the app running on that same
  machine claims it by pasting, so refusing to issue a link there leaves an owner
  who logged out with no way back in.
- **The service page checks the `Host` header.** The loopback socket keeps the
  network out; this keeps the operator's own browser out. Any site can be rebound
  to 127.0.0.1 by DNS and read the page as same-origin - and the claim link with
  it - and the request really does arrive from loopback, so the socket cannot
  help.
- **The listener's OWN address is verified after binding.** The config check
  catches a mistyped flag; a hostname can resolve to loopback at parse time and
  elsewhere at bind time, and only the socket knows which happened.
- **A busy status port does not stop the server.** It is logged and the page is
  skipped: 8081 is not a rare port, and people talking to each other must not
  depend on a page nobody has opened.
- **The TOKEN is cached, never the built link.** Caching the link froze an
  address for the life of the process while "can a phone reach us" went on being
  recomputed, so a laptop whose network came up after the server did drew a QR
  over a link that still said 127.0.0.1. One fact, one cache.
- **The held claim token is re-checked before it is shown.** It can be spent
  between two page loads - somebody claims, the owner later revokes their last
  device - and handing back the burnt one would point the only recovery tool
  there is at a door that no longer opens.
- **The claim link's address is NOT `listenAddress`.** That falls back to
  loopback under a wildcard bind, which nothing but this machine can dial - and
  the page's reader is a phone reading the code off the screen. The page
  resolves a dialable address instead (`dialableHost`). Only when the machine
  has none does the link carry loopback, and then no code is drawn - unless the
  link also carries a public or onion address, which a phone reaches wherever
  the bind is.
- **The page decides between its two states on the SAME ownership predicate**
  the startup announcement uses. A second definition of "claimed" is how phase
  033's one fact would go back to living in two records - and this one would
  show a status page to somebody locked out of their own machine.
- **Known narrow window:** the greeting reads the person from the
  store and writes it to the connection a few lines later, and the fan-out
  helpers match connections by `identity.UserID` - which is empty in between. A
  rename landing in that gap is overwritten by the write, and no
  `identity.updated` goes to that connection, so a stable socket keeps the old
  name until something reconnects it. `announcePaired` (038) inherits the same
  window with a softer consequence: a connection greeting at that moment is not
  told about the new device, and reads the list when its screen opens - which is
  where every device that was offline ends up anyway. Closing it properly means
  holding the connection registry lock across a store read, which invariant 4
  exists to forbid; recorded rather than papered over.
- **Fan-outs run AFTER the reply, never before it.** `send` blocks on a full
  write queue until that connection's context is cancelled, so announcing first
  puts the caller's own answer behind a stranger's backlog - and a wedged
  connection whose drop is still finishing its close handshake is seconds wide.
  `device.revoke` set the order; `pair` and `identity.setLabel` follow it since
  038. What the order does NOT buy: the fan-out still runs on the caller's read
  goroutine, so the same wedged recipient delays that connection's NEXT command.
  That wait is bounded by the close handshake rather than open-ended, and taking
  it away means putting the fan-out on its own goroutine - which would make
  these the only frames with no order relative to the ones around them.
- The claim token has NO expiry. It dies by being used, only someone with
  access to the machine ever sees it, and an expiring one would leave an
  installed-then-forgotten server unclaimable with no way to mint another.
  Device invites do expire, after ten minutes.
- Ownership is a reference on `server_identity`, not a flag on `users`. The
  table holds one row by CHECK, so "two owners" is unrepresentable without an
  index anyone has to remember. It is written in the transaction that creates
  the person and never derived from who is oldest: row order is not a right.
- A second PERSON is unrepresentable by index (`idx_users_singleton` over the
  constant expression `(1)`), not by convention. The consequence is deliberate
  and easy to undo by accident: a claim against a store that holds a person but
  no ownership mark now ATTACHES to that person instead of being refused. The
  refusal existed because picking an owner out of several rows by order would
  hand somebody else's history away; with one row there is nobody to pick
  wrongly, and refusing would leave a full history permanently unreachable.
- `claimed_at` is NOT the state machine. "Claimed" means "has an owner", and
  nothing reads the timestamp to decide anything - one fact in two records is
  the shape that eventually disagrees with itself. The timestamp is still
  written, in the same statement as the owner, because the moment is
  unrecoverable and the service page will want it.
- The server's private key lives INSIDE the database file - an Ed25519 seed in
  `server_identity`. The model's case 6 warns that a backup holding only the DB
  would leave the devices facing a stranger; one artifact makes that impossible,
  and anyone who can read the file already has every message.
- **Two keys, two jobs.** The machine's Ed25519 key is what devices check in the
  channel exchange and what the pairing link carries (32 bytes, no fingerprint);
  the TLS certificate's key is a throwaway P-256 minted in memory at every start
  and checked by nobody. Mixing them up - pinning the certificate, or putting the
  machine key into TLS - brings back exactly what 044 removed.
- **The server accepts every key that proves itself.** Refusing unknown keys at
  the channel would make pairing impossible (a new device is unknown by
  definition) and would tell a stranger which keys are paired. Rights come from
  the store, per command: `pair` for anyone, everything else for paired keys.
- **A failed check is answered with silence.** The server writes nothing - not
  even its own message - and closes the connection; a peer that did not prove a
  key learns nothing, including which machine it reached.
- **A key nobody paired gets one request per connection, and on `/ws` two
  minutes and 32 such sessions at once** (045: the onion service is open to
  anybody who knows its address, and a key made for the occasion passes the
  channel check). Off `/ws` every answer ends the connection, and a body it
  declared is not awaited past an answer of ours (an answer net/http gives
  itself, to an unsupported Expect, waits for it 30 s at most): kept open, a
  connection would stay a stranger's for as long as it asked again within
  each idle timeout - or, with a body declared and never sent, for good
  without another byte. On `/ws`, past the cap the OLDEST is closed for the
  newcomer, never the newcomer: a refusal
  would let 32 connections renewed every two minutes keep every new device
  from pairing, where closing the oldest makes a stranger open 32 within each
  of a device's round trips. **046 must extend or exempt the deadline** for a
  pairing that waits on the person's approval (up to an invite's ten
  minutes), and keep such a connection from being the oldest a flood closes,
  or every slow approval fails. What stays open: within its two minutes a
  stranger may send `pair` as often as it likes, each failed attempt one
  short write transaction on the single writer; and the connections past the
  check are not capped as a whole - a stranger may open them one after
  another, each held for one request's budgets (30 s for its headers) at the
  price of a full handshake, so what bounds how many it holds is how fast it
  can complete handshakes.
- **This machine is one source on the channel's entry, and its share is
  bounded** (64 of 256). tor is not told apart from any other process here:
  the app running on the server's own machine shares the share and the
  first-byte exemption with every device away from home. A flood through the
  onion service can therefore cut the handshakes of an app ON the machine
  too - never those of a device at home.
- **No migration for a database from before 044** and there will not be one:
  `001_init.sql` was edited in place, the schema check refuses an old file, and
  the cure is a new database and every device paired again.
- The claim link goes to the service page and NOWHERE else (045). The startup
  line says where the page is (`service_page`), never what the link is: the
  link carries the claim token and, packed, the onion service's key, and a log
  is copied to places neither may go - a bug report, a support thread, a
  collector. With `-status-addr` empty that line is a warning that nothing
  shows the link. Which is why the page listens on loopback only and refuses
  to start anywhere else: encryption stops somebody reading the link off the
  wire, and does nothing about a page that hands it to whoever asks. The
  loopback bind is what answers that, and `assertLoopback` checks the socket
  rather than the string somebody typed.
- The CLAIM link carries a dialable address of this machine (the page's choice
  above), while an INVITE link uses the address the requesting device dialled
  (its `Host` header) - or, for a request through the onion service, where
  `Host` is the onion name, the head of the direct list
  (`inviteDirectAddress`). An invite is carried to another device, so it names
  the address a device of this person has just reached the machine at. Both
  carry the stored public address first and the onion address last when they
  are set.
- `users.label` is neither unique nor validated (owner, 2026-09-02): a
  greeting may never be refused because of a name, since the client
  retries a refused greeting forever.
- No push, no `chat.markRead`, message `body` is open text — all gated
  by open questions; see contract §8 before touching.
- Cyrillic never appears in code, comments, or commit messages.
