# CLAUDE.md — NOX client server (Go)

Self-hosted messenger backend for ONE person and the devices they own:
one WebSocket command channel (JSON envelope, global `seq` event log,
cursor replay) plus a small REST surface (file upload/download), both behind
the channel check of feature 044, embedded SQLite, single static CGO-free binary - and, since 039, a tor
process beside it that the server starts, supervises and stops, and that
never opens the database. Different people never
share a machine and their machines never talk to each other — everything
between people goes through a relay whose protocol does not exist yet
(Q13).

**The contract is law:** `docs/client-backend/protocol/contract-draft.md`
(v0). Every command, event, field name, error code and rule comes from
there; a change needed on the wire is first a contract edit, then code.

**Who connects is decided by the channel (feature 044).** Every connection -
the WebSocket and every file transfer alike - is TCP (or a stream from tor),
then TLS 1.3 on a THROWAWAY certificate the server mints in memory at every
start and nobody checks, then the Eidolon exchange over the TLS 1.3 exporter
(RFC 9266, `internal/eidolon`): the device sends its Ed25519 key with a
signature over the key and one over the binding, the server checks both and
answers with the machine's own Ed25519 key the same way. Only then does
`http.Server` see the connection, carrying the device key it proved
(`channelPeer`). The server accepts ANY key that proves itself and grants
rights by the store: a paired device gets everything, an unknown key only
`pair` and `pair.cancel`; `session.hello` with an unknown key is
`unauthenticated` (the device reads it as a revocation), and `/files` refuses
an unpaired key with `401` before it looks at the token. The greeting has no
challenge, `session.hello` and `pair` carry no device key, and the pairing
link is `nox://pair/` version 3 (contract §8A).

**A device joins one of two ways (feature 046, contract §8A).** The MACHINE
LINK is handed out on the machine itself - by the service page (at once while
no device is paired, otherwise on `Add a device` / `New link`) or by
`noxd link` - lives ten minutes, is the only live one (a new link voids the
one before), and pairs at once: it creates the person when there is nobody,
and joins them, with everything they wrote, when there is. A device INVITE
(`device.invite`, ten minutes) pairs nothing by itself: `pair` with it opens
a request, the issuing device is asked (`device.pairRequested`) and answers
with `device.approve`, and the request closes exactly once - allowed, denied,
expired, cancelled by the new device (`pair.cancel`), or denied because a
device taking part in it was revoked. People come into being only through
`pair` with a machine link. The machine belongs to ONE person (037) and there
is no owner beside them: whether anybody can reach the machine is the device
count, and the last device going away puts the service page back to showing a
link. There is no separate recovery - no phrase, no codes: the machine link
is the way back. No link and no token ever reaches the log. Still out of
scope and blocked: the protocol to the relay (Q13), and ATS / App Review for
a personal server reached through the app's own Rust module (Q14, due before
release).

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
    ./noxd link -qr           # a machine link from the RUNNING server, drawn as a code too
                              # (-status-addr names its service page, default 127.0.0.1:8081)
    go run ./cmd/smoke '<machine link>'   # the whole pairing flow against a running server

## Toolchain & dependencies

- Go **1.27**. Direct dependencies: exactly four — `github.com/coder/websocket`,
  `modernc.org/sqlite`, `golang.org/x/sync` (errgroup) and `rsc.io/qr`. Adding
  any other requires written justification; "convenient" is not one.
- **Why `rsc.io/qr` (035):** encoding a QR is a whole capability — Reed-Solomon
  over GF(256), version selection, eight masks scored by penalty — not a
  convenience, and writing it here buys nothing but our own bugs in the thing
  people scan to pair a device with their server - on the service page, and in
  the terminal for `noxd link -qr`. Pure Go, no dependencies of its own, no
  CGO, so `CGO_ENABLED=0` static builds are untouched.
- `modernc.org/libc` does not follow semver — its version stays pinned;
  bump only together with `modernc.org/sqlite` and run the full test suite.
- Dev tools go through `tool` directives in go.mod (Go 1.24+), never a
  `tools.go` with blank imports.

## Architecture invariants (MUST hold after every change)

1. **Exactly one OS process opens the database file.** No sidecars that
   touch the database, no cron, no second node. The ONE other process is
   tor (039): the server starts it with its own empty config and its own
   state directory `<db>-tor`, commands it over the control port, owns it
   (`__OwningControllerProcess` + `TAKEOWNERSHIP`, so it dies with the
   server) and hands it the onion key on every start - tor never opens the
   database and never persists the key.
2. **Two pools, one writer.** All writes go through `internal/store`
   using the write handle (`SetMaxOpenConns(1)` + `_txlock=immediate`);
   reads use the read pool. Never `Exec` a mutation on the read handle;
   never add a second write handle; never write outside `internal/store`.
3. **Transactional outbox.** Every mutation visible on the wire as an
   event inserts its `events` row in the SAME transaction; broadcasting
   happens only AFTER `Commit` returns (via the dispatcher). Never
   broadcast inside a transaction. Three lifecycles are deliberately
   event-less: file metadata (upload registration, continuation,
   mark-uploaded, orphan sweep), because files surface to other clients
   only through `message.send`; identity resolution (`internal/store/identity.go`),
   because a PERSON coming into being is not visible on the wire at all; and
   pairing - tokens, requests and the device rows they write
   (`internal/store/{pairing,requests,devices}.go`) - because who may reach
   the machine is not the shared world the journal records.
   The rule is about the JOURNAL, and the off-journal events sit outside it by
   construction: `device.revoked`, `identity.updated`, `device.paired` (038)
   and the three of pairing with approval (046) - `pair.resolved`,
   `device.pairRequested`, `device.pairResolved` - carry `seq: 0`, write no
   `events` row, take no cursor coordinate and are never replayed. They
   describe who a connection is, who may join the machine or what a
   connection may still do, not what happened in the shared world, which is
   why a disconnect may lose them. What must not be lost has a reliable half
   on the store: a revoked device is `unauthenticated` at its next greeting; a
   new device repeats `pair` with the same token from the same key and is
   answered with its request's recorded outcome (`pending` while it waits);
   the issuing device is sent every request still waiting for its answer
   again after each of its greetings, and an answer to a request that closed
   meanwhile is `not_found`.
   `server.addresses` (039) is one more: it says where this machine can be
   reached, has ONE sender - the address watcher - and the greeting reply is
   its reliable half.
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
   fields other goroutines read (identity, `greeted`, `addrVersion`),
   because the fan-out helpers walk one person's - or one device key's -
   connections from somewhere else: another connection's command, the
   address watcher, the request sweeper. They collect under the lock and
   send outside it (`connectionsWhere`). The device key needs no lock: the
   channel fixes it before the connection is registered, and it never
   changes.
   The transfer-token store (`internal/server/tokens.go`) and - since 043 -
   the upload-writer registry (`internal/server/writers.go`: which request is
   writing which part, so a new PUT can interrupt one whose connection died
   silently instead of writing beside it) hold the only other two. The mutex
   inside each PUT's `stallReader` (`files.go`) is NOT a third: it lives and
   dies with one request, guards nothing another request or connection reads,
   and only orders that request's read-deadline renewal against an interrupt,
   so the interrupt is never pushed back by a whole stall timeout. `greeted`
   and `addrVersion` are set under `Server.mu` AFTER the greeting reply is
   queued, which is what keeps `server.addresses` behind it; the requests
   waiting for the device's answer are re-sent only after that mark, so a
   request opened during a greeting reaches the issuer one way or the other.
   PAIRING holds no lock of its own: tokens, requests and devices change only
   inside store transactions, the single writer puts them in one order, and a
   conditional UPDATE's affected-row count settles every race - two devices
   presenting one token, an Allow against the deadline against a cancel. The
   address snapshot reaches readers behind an `atomic.Pointer` that the
   watcher alone writes, not under a lock.
8. **One reader goroutine per connection** (library invariant); writes
   to a client go through its buffered channel (`outBuffer` = 64 frames); overflow →
   `Close(StatusPolicyViolation)` — replay heals the client on
   reconnect. Keepalive: own ticker with `Ping(ctx)` ~25s, on a goroutine
   BESIDE the writer - Ping waits a whole round trip, which over Tor is
   seconds, and a writer parked on it lets live frames overflow the queue.
   `SetReadLimit(max_frame_bytes)`.
9. **Shutdown order:** the HTTP servers drain (the main one, then the
   service page, each on its OWN deadline) →
   registered WS conns get `Close(StatusGoingAway)`, IN PARALLEL - one close
   handshake can take 10 s, and over Tor it does (Shutdown does NOT wait for
   hijacked conns — keep the conn registry wired via `RegisterOnShutdown`) →
   wait for the handlers, up to 15 s → the address watcher and the request
   sweeper stop, each on its OWN context (both send to connections that are
   still being told goodbye, and both use the database - the sweeper writes
   it) → hub stops → DB closes. Preserve it.
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
  one of the event-less lifecycles of invariant 3
- `internal/store/serverkey.go` — the machine's own Ed25519 key pair on the
  single `server_identity` row. No owner: "can anybody reach this machine" is
  `countDevices`, the one spelling of it, asked by the service page, the
  startup line and the last device going away
- `internal/store/pairing.go` — the two kinds of one-shot token and `Pair`:
  the machine link (at most one unspent - issuing one voids the others in the
  same transaction; minted by `noxd link`, by the page's buttons, and by the
  page itself while no device is paired and no unspent link exists) and the
  device invite, which remembers its issuer. Burning is a conditional UPDATE
  whose affected-row count settles a two-device race
- `internal/store/requests.go` — requests to join through an invite (046):
  opened by `pair`, found again by the key that opened them, closed exactly
  once - allowed (the device row is written in the same transaction), denied,
  expired, cancelled - and the invite spent whatever the outcome
- `internal/store/devices.go` — device list, revocation (DELETE, so a revoked
  device is indistinguishable from an unknown one; the same transaction
  closes the requests it takes part in, on either side, as denied, voids its
  unspent invites, and - when it was the last device - voids a machine link
  that ran out unused, so the page leads with a fresh one), rename
- `internal/store/accesskeys.go` — onion access keys (039): one per device,
  the active set read in one transaction (the one-time invite keys left with
  044; the rest leaves with 045)
- `internal/tor/`        — everything that knows about tor (039): finding and
  versioning the binary, the control-protocol client, the onion key and
  address, the supervisor that owns the process and publishes the service,
  and the log scrubber. The onion seed never leaves this package once handed
  in at startup
- `internal/server/addresses.go` — where this machine can be reached: the
  versioned snapshot, the watcher that is the only sender of
  `server.addresses`
- `internal/hub/`        — fan-out goroutine owning the subscriber set
- `internal/protocol/`   — envelope v0 types, error codes, frame (un)marshal
- `internal/server/`     — ServeMux wiring: `/ws`, REST (§1 of contract), middleware
- `internal/eidolon/`   — the channel check (044): the 160-byte message, the
  responder the server runs and the initiator `cmd/smoke` and the tests run;
  shared vectors with the app's Rust module in `testdata/vectors.json`
- `internal/server/channel.go` — the front door: a listener wrapper that takes
  every connection through TLS and the check on a goroutine of its own, under
  one deadline from accept (10 s direct, 30 s onion), and hands `http.Server`
  only the ones that passed, with the proved key in the request context
- `internal/server/tls.go` — the technical certificate: a fresh ECDSA P-256 key
  in memory at every start, TLS 1.3 only, ALPN `http/1.1`, no session tickets
- `internal/server/pairing_link.go` — the version 3 link: build and parse, typed
  addresses, shared vectors with the app in `testdata/link-vectors.json`
- `internal/server/pairing.go` — the device commands of contract §8A: `pair`
  and `pair.cancel` (the two allowed before a greeting), `device.approve`,
  `device.list`, `device.invite`, `device.revoke`, `identity.setLabel`
- `internal/server/requests.go` — who hears what about a request, and when:
  `device.pairRequested` to the issuing device's greeted connections (and
  again after each of its greetings), `pair.resolved` to the new device's
  connections that have not greeted, `device.pairResolved` to the issuer;
  and the sweeper (`Server.requestSweep`, 2 s) that closes what ran out
- `internal/server/status.go`, `status_page.go`, `status_qr.go` — the service
  page on its own loopback listener: the machine's state, the machine link
  with its countdown, `Add a device` / `New link` (`POST /link`) and the
  address forms (`POST /addresses`), both forms checked for this page's
  `Origin` and the per-process form token; the QR as SVG for the page and as
  text for `noxd link -qr`
- `internal/server/control.go` — `POST /control/link` on that same listener,
  the whole of `noxd link` but the printing: a local `Host`, `X-Nox-Control: 1`
  and NO `Origin`, or 403. The command never opens the database (invariant 1):
  it asks the running server
- `internal/server/files.go` — the file chain (contract §7): `file.uploadBegin`
  with its continuation (`file_id` in, `received` out), the PUT that keeps
  whatever arrives and carries the rest of the file from the offset its token
  names, the GET with Range/If-Range; a body is cut by silence alone (043).
  A new upload token revokes the file's earlier ones, so a PUT that turns up
  late cannot cut the part back past what a newer attempt wrote; and the PUT
  reads the row again once it holds the file, so a token issued before the
  file was finished cannot write over it
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
- "No link and no token in the log" is a test, not a promise:
  `TestNoLinkAndNoTokenEverReachesTheLog` (`logs_test.go`) drives `Run` itself
  and reads everything the process says while links are issued - by the page,
  its buttons and `noxd link` - and spent: a machine link, and an invite with
  its request and its Allow.
- Concurrency/replay tests may use `testing/synctest` (GA since 1.25).
- Tests through the REAL Tor network are named `TestOnion*` and run only
  when `NOX_TOR_TEST_BIN` points at a tor binary (0.4.9+); without it they
  skip, because the network is minutes away and not always reachable.
  Everything else about tor is tested on fakes of the control connection and
  the process launcher.
- Always `go test -race ./...`.

## Operational constraints

- Bind loopback in dev. The listener is TLS 1.3 and the channel check either
  way: there is no flag to serve plaintext or skip the check, and adding one
  would be adding the downgrade the whole design removed. The SERVICE PAGE is
  the deliberate exception and stays plain HTTP on its own loopback listener,
  together with `GET /health` and `POST /control/link`, where `noxd link` asks
  for a machine link: the main port answers nothing before the check.
- Backups: `VACUUM INTO` a temp file + rename; never copy a live DB;
  local filesystem only (WAL breaks on network mounts).
- Build: `CGO_ENABLED=0 go build -trimpath -ldflags="-s"`.
- Tor (039) is ON by default: `-tor=false` turns it off. The binary comes
  from `-tor-bin` (final - an explicit path that holds no tor is "not
  found", never a reason to look elsewhere), else next to `noxd`, else
  `PATH`; 0.4.9 is the floor. Linux distribution packages are often older -
  use the Tor Project repository. The official macOS tor is UNSIGNED and
  killed at launch on Apple Silicon until signed (ad-hoc is enough for dev).
  Its state lives in `<db>-tor` (a cache, outside backups; it holds the
  control cookie, so never commit it). tor runs in a process group of its
  own, so a terminal's Ctrl+C reaches only the server, which drains and then
  stops tor; a systemd unit needs `KillMode=mixed`, because the default
  `control-group` signals every process of the unit at once.

## Known deliberate omissions (do not "fix" silently)

- **A file transfer has no time limit, only a stall limit** (043). The body
  deadline is renewed before every read (PUT) and every write (GET), so a
  transfer is cut after 60 s without a byte and never for taking long:
  through Tor 100 MiB take tens of minutes, and any limit on the whole cuts
  exactly the path away from home. The price is known: a connection trickling
  a byte a minute holds a goroutine for as long as it likes. Its holder is one
  of the person's own devices - a token goes only to a greeted connection.
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
  Copy button and puts the machine link on the clipboard - two lines of base64
  are not something to select by hand - and counts the minutes the link has
  left, turning into `Link expired` with `New link` when they run out, so a page
  left open never offers a code that stopped working. It mints nothing: a new
  link only ever comes from a button. Three things keep it from being a hole,
  and undoing any of them reopens one: the button ships HIDDEN and the script
  reveals it, so a page whose script did not run shows no dead control; the
  policy names `script-src 'sha256-...'` and never `'unsafe-inline'`, so exactly
  those bytes may run; and `default-src 'none'` still forbids `connect-src`, so
  the script can read the link and has nowhere to send it. The hash is DERIVED
  from the script constant on every response rather than written down: a stored
  derivative is a second copy of one fact. A page with no LIVE link carries no
  script and its policy admits none.
- **Clipboard access needs a secure context, and this page has one without TLS.**
  `http://127.0.0.1` and `http://localhost` are potentially trustworthy origins;
  measured in a browser, not assumed. The fallback still exists: if the API is
  missing or refuses, the script selects the link so one keystroke finishes it.
- **At most one machine link is unspent, and nothing mints over one on its
  own.** Issuing a link voids every earlier unspent one in the same
  transaction, so whatever the page showed or `noxd link` printed stops working
  the moment a newer one exists. The page mints by itself only while no device
  is paired AND no unspent link exists: a reload never mints, and a link that
  ran out is never replaced behind anybody's back - the page says
  `Link expired` and waits for `New link`. While devices exist the page shows a
  link only on `Add a device`, so a page merely left open holds no live way in.
- **A loopback bind draws no CODE, but still shows the LINK.** Two questions, and
  conflating them cost the page once: "can a phone dial this" decides the QR, and
  nothing decides whether a link exists. The default `-addr` is `127.0.0.1:8080`,
  where a phone cannot reach the server at all - but the app running on that same
  machine pairs by pasting the link, so refusing to issue one there leaves a
  person who signed out of their last device with no way back in. `noxd link -qr`
  follows the same rule: no code for a link only this machine can follow.
- **The service page checks the `Host` header.** The loopback socket keeps the
  network out; this keeps the operator's own browser out. Any site can be rebound
  to 127.0.0.1 by DNS and read the page as same-origin - and the machine link
  with it - and the request really does arrive from loopback, so the socket
  cannot help. Its forms (`POST /link`, `POST /addresses`) also need this page's
  own `Origin` and the per-process form token, which a page from elsewhere
  cannot read. `POST /control/link` turns the rule around - `X-Nox-Control: 1`
  and NO `Origin`: a browser always sends an `Origin` on a POST, and the custom
  header forces a CORS preflight nothing here answers, so a page from another
  site never gets as far as sending it, while `noxd link` sends exactly that.
- **The listener's OWN address is verified after binding.** The config check
  catches a mistyped flag; a hostname can resolve to loopback at parse time and
  elsewhere at bind time, and only the socket knows which happened.
- **A busy status port does not stop the server.** It is logged and the page is
  skipped: 8081 is not a rare port, and people talking to each other must not
  depend on a page nobody has opened. Without the page there is no machine link
  at all - neither the page nor `noxd link` - which is why an empty
  `-status-addr` on a machine with no device yet is logged as an error.
- **Only the TOKEN is stored, never the built link.** The page and `noxd link`
  rebuild the link from the unspent token whenever they are asked, and the
  address in it is resolved at that moment. A built link kept for later froze an
  address while "can a phone reach us" went on being recomputed, so a laptop
  whose network came up after the server did drew a QR over a link that still
  said 127.0.0.1. One fact, one record.
- **The machine link's address is NOT `listenAddress`.** That falls back to
  loopback under a wildcard bind, and the link is carried to ANOTHER device. It
  names the address another device can dial - the bind when it names one, else
  the first interface that is up, IPv4 first - and falls back to loopback only
  when the machine has nothing else; a code is then drawn only when a public or
  onion address in the link still gives a phone a way in. An INVITE
  link takes the address the requesting device dialled instead (its `Host`
  header; through the onion service, the first found direct address): that
  device demonstrably reached the server there, while the machine link has no
  device asking yet.
- **"Can anybody reach this machine" has ONE answer: `countDevices`.** The
  page's two states, the startup line that says where a link is, and the last
  device going away all ask it. There is no owner marker beside it: a second
  record of one fact is the shape that eventually disagrees with itself, and
  here the disagreement would be a page that hides the link from somebody
  locked out of their own machine.
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
  `device.revoke` set the order; `pair`, `pair.cancel`, `device.approve` and
  `identity.setLabel` follow it. What the order does NOT buy: the fan-out still
  runs on the caller's read goroutine, so the same wedged recipient delays that
  connection's NEXT command.
  That wait is bounded by the close handshake rather than open-ended, and taking
  it away means putting the fan-out on its own goroutine - which would make
  these the only frames with no order relative to the ones around them.
- **Both kinds of pairing token live ten minutes.** A link that does not expire
  is a standing way in for whoever kept a copy, and a device can pair through
  the onion service from anywhere. Nobody is locked out by the deadline: the
  machine link can always be issued again on the machine, and a request lives
  no longer than the invite it was opened with.
- **A request ends within one sweep of its deadline, not to the second.** The
  sweeper looks every 2 s; an exact timer per request would be state to keep in
  step with the store for no difference anybody sees against ten minutes. The
  deadline itself is exact where it decides something: `device.approve` at or
  past it is `not_found`, and a repeat of `pair` past it closes the request as
  expired on the spot. Asking the store costs a read when nothing is due - the
  writer is taken only when something is.
- A second PERSON is unrepresentable by index (`idx_users_singleton` over the
  constant expression `(1)`), not by convention. The machine link therefore has
  nobody to choose between: it creates the person when there is nobody and joins
  them when there is - and it is never refused because devices exist or because
  the person exists. That is deliberate and easy to undo by accident: the
  machine link is the only way back for somebody who lost every device, whoever
  can issue it already holds the machine and its database, and refusing would
  leave a full history permanently unreachable.
- **Revocation closes requests on BOTH sides.** A revoked issuer can answer
  nothing, so its waiting requests close as denied rather than holding the new
  device at its screen for the rest of the ten minutes, and its unspent invites
  are voided - a link from a device just told to leave must not ask the
  person's other devices for anything. A revoked device that was itself asking
  to join is denied too: the person who revoked it is not to be asked to let it
  back in on a request it opened before.
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
  the store, per command: `pair` and `pair.cancel` for anyone, everything else
  for paired keys.
- **A failed check is answered with silence.** The server writes nothing - not
  even its own message - and closes the connection; a peer that did not prove a
  key learns nothing, including which machine it reached.
- **An unpaired key may hold a `/ws` connection open without greeting.** There
  is no greeting deadline; the cost is a goroutine per idle stranger, bounded by
  `maxPendingChannels` only while the check runs. A device waiting for Allow
  does exactly this, for at most its invite's ten minutes. Recorded, not fixed.
- **No migration for an older pre-release database**, and there will not be
  one: `001_init.sql` is edited in place, the schema check refuses a file
  written from another 001 (by the fingerprint of the migration text), and the
  cure is a new database and every device paired again.
- **No link and no token ever reaches the log.** The log is kept, copied and
  shipped, while a link is a way in for ten minutes. The startup line, when no
  device can reach the machine, names the service page and `noxd link` - never
  a link; issuing one logs who asked (`service page` or `noxd link`), a closed
  request logs its outcome, and nothing names a device, a token or an address
  in a link. A machine link goes to the service page and to the terminal that
  ran `noxd link`, an invite to the device that asked for it, and neither goes
  anywhere else - which is why the page listens on loopback only and refuses
  to start anywhere else. TLS does NOT retire that reasoning:
  encryption stops somebody reading the link off the wire, and does nothing
  about a page that hands it to whoever asks. The loopback bind is what answers
  that, and `assertLoopback` checks the socket rather than the string somebody
  typed.
- **There is no revocation on the service page.** A lost device is revoked from
  a device the person holds - the one just added with a machine link included.
  The page hands out a way in; it does not judge which devices stay.
- `users.label` is neither unique nor validated (owner, 2026-09-02): a
  greeting may never be refused because of a name, since the client
  retries a refused greeting forever.
- No push, no `chat.markRead`, message `body` is open text — all gated
  by open questions; see contract §8 before touching.
- Cyrillic never appears in code, comments, or commit messages.
