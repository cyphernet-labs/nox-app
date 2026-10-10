# CLAUDE.md — NOX client server (Go)

Self-hosted messenger backend for ONE person and the devices they own:
one WebSocket command channel (JSON envelope, global `seq` event log,
cursor replay) plus a small REST surface (file upload/download), both behind
the channel check of feature 044, embedded SQLite encrypted at rest and locked
after every start until the owner's password comes (047), single static
CGO-free binary. tor, when the machine has one, is a separate OS service set
up by hand or by the install script (049): it publishes the onion service and
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
`pair` and `pair.cancel` - within two minutes, on one of at most 32 such
connections (`unpaired.go`), unless an invite it presented waits for Allow:
that connection waits, free of both, until the request closes (046);
`session.hello` with an unknown key is `unauthenticated` (the device reads it
as a revocation), and `/files` refuses an unpaired key with `401` before it
looks at the token. Off `/ws` an unknown
key gets one request per connection: the door in front of the mux
(`limitStrangers`) ends the connection with every answer but a WebSocket
upgrade. The greeting has no challenge, `session.hello` and `pair` carry no
device key, and the pairing link is `nox://pair/` version 3 (contract §8A).

**A device joins one of two ways (feature 046, contract §8A).** The MACHINE
LINK is handed out on the machine itself, once its password has opened it - by
the service page (at once while no device is paired, otherwise on `Add a
device` / `New link`) or by `noxd link` - lives ten minutes, is the only live
one (a new link voids the one before), and pairs at once: it creates the
person when there is nobody, and joins them, with everything they wrote, when
there is. A device INVITE (`device.invite`, ten minutes) pairs nothing by
itself: `pair` with it opens a request, the issuing device is asked
(`device.pairRequested`) and answers with `device.approve`, and the request
closes exactly once - allowed, denied, expired, cancelled by the new device
(`pair.cancel`), or denied because a device taking part in it was revoked.
People come into being only through `pair` with a machine link. The machine
belongs to ONE person (037) and there is no owner beside them: whether
anybody can reach the machine is the device count, and the last device going
away puts the service page back to showing a link. There is no separate
recovery - no phrase, no codes: the machine link is the way back, and a
backup is the way back for the machine itself (047). No link, no token, no
password and no key ever reaches the log. Still out of scope and blocked: the
protocol to the relay (Q13), and ATS / App Review for a personal server
reached through the app's own Rust module (Q14, due before release).

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
    ./noxd unlock             # the password: set the first time, entered after every start
    ./noxd link -qr           # a machine link from the RUNNING, unlocked server, drawn as a code too
    ./noxd password           # a new password - the data key is re-sealed, nothing re-encrypted
    ./noxd backup /abs/nox.tar                    # one encrypted file, written by the running server
    ./noxd restore nox.tar -db /new/place/nox.db  # onto an empty place, no server running there
                              # (the commands but restore find the service page by -status-addr,
                              # default 127.0.0.1:8081)
    go run ./cmd/smoke '<machine link>'   # the whole pairing flow against a running server

## Toolchain & dependencies

- Go **1.27**. Direct dependencies: exactly seven — `github.com/coder/websocket`,
  `github.com/ncruces/go-sqlite3`, `golang.org/x/crypto`, `golang.org/x/sync`
  (errgroup), `golang.org/x/term`, `lukechampine.com/adiantum` and `rsc.io/qr`.
  Adding any other requires written justification; "convenient" is not one.
- **Why `ncruces/go-sqlite3` (047):** it is the one SQLite for Go that encrypts
  page by page without CGO - SQLite compiled to WebAssembly and run in-process by
  wazero, with the `adiantum` VFS that encrypts every page of the database and of
  its WAL with the data key. `modernc.org/sqlite` has no encrypting VFS, and
  writing one over it means rewriting SQLite's VFS layer; SQLCipher is CGO.
  Its own dependencies come with it: the Wasm build of SQLite
  (`go-sqlite3-wasm`), `lukechampine.com/adiantum` and `x/sys`. Bump it only
  with the full suite run: the Wasm build carries SQLite's own version, and
  `internal/db`'s key check reads the files the way its VFS writes them.
- **Why `lukechampine.com/adiantum` (047):** the cipher the `adiantum` VFS
  encrypts with, already in the binary through it, imported directly for ONE
  job: telling a data key that is not the database's before SQLite opens
  anything (`internal/db/keycheck.go`). SQLite finds out only after it has run
  WAL recovery with that key, and then deletes the WAL it could not read -
  committed transactions with it. Reaching the cipher through the VFS instead
  would mean opening the file through SQLite, which is the very thing to
  avoid.
- **Why `golang.org/x/crypto` (047):** Argon2id derives the key that seals the
  data key from the owner's password, XChaCha20-Poly1305 seals it and
  ChaCha20-Poly1305 seals each attachment chunk. Writing any of them here would be
  writing our own cryptography. HKDF comes from the standard library
  (`crypto/hkdf`).
- **Why `golang.org/x/term` (047):** `noxd unlock`, `noxd password` and `noxd
  restore` read the password from a terminal without echo, on every platform the
  server runs on; the standard library has no way to turn echo off.
- **Why `rsc.io/qr` (035):** encoding a QR is a whole capability — Reed-Solomon
  over GF(256), version selection, eight masks scored by penalty — not a
  convenience, and writing it here buys nothing but our own bugs in the thing
  people scan to pair a device with their server - on the service page, and in
  the terminal for `noxd link -qr`. Pure Go, no dependencies of its own, no
  CGO, so `CGO_ENABLED=0` static builds are untouched.
- Dev tools go through `tool` directives in go.mod (Go 1.24+), never a
  `tools.go` with blank imports.

## Architecture invariants (MUST hold after every change)

1. **Exactly one OS process opens the database file, and the server spawns
   NO process at all.** No sidecars that touch the database, no cron, no
   second node, no child process of any kind. tor is a separate OS service
   (045): it never opens the database, the server never starts, commands or
   stops it, and all the server knows of it is the onion address stored in
   `server_identity`. `run_test.go` holds that `Run` starts no tor even with
   one on the PATH. The `noxd` commands never open the database either:
   `link` (046), `unlock`, `password` and `backup` (047) go to the running
   server over its service page's listener, and `restore` opens only the copy
   it is putting into an empty place, where no server runs.
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
   fields other goroutines read (identity, `greeted`, `addrVersion`),
   because the fan-out helpers walk one person's - or one device key's -
   connections from somewhere else: another connection's command, the
   address watcher, the request sweeper. They collect under the lock and
   send outside it (`connectionsWhere`). It guards `transfers` too - the
   `/files` requests under way, each registered under the key its connection
   proved - because a revocation on one connection cuts another device's
   transfers, which since 044 run on connections of their own. It guards
   `unpaired` as well - the /ws connections of keys nobody paired, oldest
   first, each holding its own place in the list (`unpaired.go`) - because a
   newcomer's handler takes the oldest of them out to make room, and each
   one's deadline fires on a timer's goroutine; and `waits`, the connection
   waiting on each pairing request (046), because the request closes on
   whichever goroutine closed it - an answer, a cancel, the sweeper, a
   revocation - and that goroutine puts the waiting connection back among
   the strangers or lets it go. The device key needs no lock: the channel
   fixes it before the connection is registered, and it never changes.
   The transfer-token store (`internal/server/tokens.go`), the upload-writer
   registry (043, `internal/server/writers.go`: which request is writing
   which part, so a new PUT can interrupt one whose connection died silently
   instead of writing beside it) and each channel listener's registry of
   handshakes under way (`internal/server/channel.go`: which connections are
   still proving a key, oldest first and counted per source - this machine
   being one source with a share of its own - so the accept loop can cut the
   oldest - of one source, or of all - without ever waiting) hold the only
   other three. The mutex inside each PUT's
   `stallReader` (`files.go`) is NOT a fourth: it lives and dies with one
   request, guards nothing another request or connection reads, and only
   orders that request's read-deadline renewal against an interrupt, so the
   interrupt is never pushed back by a whole stall timeout. `greeted` and
   `addrVersion` are set under `Server.mu` AFTER the greeting reply is
   queued, which is what keeps `server.addresses` behind it; the requests
   waiting for the device's answer are re-sent only after that mark, so a
   request opened during a greeting reaches the issuer one way or the other.
   PAIRING holds no lock of its own: tokens, requests and devices change only
   inside store transactions, the single writer puts them in one order, and a
   conditional UPDATE's affected-row count settles every race - two devices
   presenting one token, an Allow against the deadline against a cancel. The
   address snapshot (`addressSet`: the found addresses plus the stored public
   and onion address) reaches readers behind an `atomic.Pointer` that the
   watcher alone writes, not under a lock; there is no Tor state in the
   process. The lock of 047 holds no mutex either: every request that touches
   the key file - the first password, the password, a change, a backup - is
   served by ONE goroutine at a time (`gate.go`: Run's while the server is
   locked, the keeper's after), in the order they came, and the lock state is
   an atomic readers only load.
8. **One reader goroutine per connection** (library invariant); writes
   to a client go through its buffered channel (`outBuffer` = 64 frames); overflow →
   `Close(StatusPolicyViolation)` — replay heals the client on
   reconnect. Keepalive: own ticker with `Ping(ctx)` ~25s, on a goroutine
   BESIDE the writer - Ping waits a whole round trip, which over Tor is
   seconds, and a writer parked on it lets live frames overflow the queue.
   `SetReadLimit(max_frame_bytes)`.
9. **Shutdown order:** the HTTP servers drain (the main one, then the
   service page, each on its OWN deadline - the page cancels its requests'
   contexts first, so a backup being written stops before the database it
   reads closes) →
   registered WS conns get `Close(StatusGoingAway)`, IN PARALLEL - one close
   handshake can take 10 s, and over Tor it does (Shutdown does NOT wait for
   hijacked conns — keep the conn registry wired via `RegisterOnShutdown`) →
   wait for the handlers, up to 15 s → the gate's keeper (047), the address
   watcher and the request sweeper stop, each on its OWN context (the watcher
   and the sweeper send to connections that are still being told goodbye, and
   all three use the database - the sweeper writes it, the keeper may be
   writing a backup out of it) → hub stops → DB closes. Preserve it. There is
   no tor to stop: it is not the server's process. Startup runs the other way
   (047): the service page comes up FIRST, before the database opens - the
   password is entered there - and everything else, the main port last, only
   once the password has opened the data.
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
13. **Pragmas are fixed** in `internal/db` for every connection, in this
    order: the data key (`PRAGMA hexkey`, run by the connection hook and
    never put in the URI - 047), then busy_timeout(5000), WAL,
    synchronous(NORMAL), foreign_keys(1) and temp_store(memory). Do not vary
    per-call.

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
- `internal/db/`         — pools, pragmas, `user_version` migration runner; the
  `adiantum` VFS keyed with the data key (047), the key checked against the
  first block of the database, its WAL and its journal before SQLite opens any
  of them (`keycheck.go`), `Snapshot` (VACUUM INTO under the same key, the key
  cut out of any error) and `QuickCheck`
- `internal/vault/`      — the data key (047): 32 random bytes, sealed in
  `<db>.key` with XChaCha20-Poly1305 under Argon2id of the password; create,
  open, change (a new seal written beside, flushed, renamed over), the password
  rule. The only place a password turns into a key
- `internal/backup/`     — `noxd backup` and `noxd restore` (047): one tar of the
  sealed key, the snapshot and the finished attachments, closed by a manifest
  with a MAC only the data key makes; the restore checks everything before it
  puts anything in place, and rotates the journal id
- `internal/prompt/`     — passwords for the commands: a terminal without echo,
  or a line at a time from standard input
- `commands.go`          — the `noxd` subcommands by name, and unlock, password,
  backup and restore (047); `link` stays in `main.go`
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
  `New` wrap whatever logger they get - `Run` before the lock, so the gate's
  lines are held to it too - and the error logs of both `http.Server`s, the
  main port's and the service page's, are routed through it): onion addresses
  become `[onion]` and pairing links `[link]`, whatever the text came from - a
  call site covers only the text its author thought of
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
  newcomer. `pair` pairing on it or `session.hello` succeeding settles it; a
  paired device's connection is never held to either limit. A `pair` that
  answers `pending` (046) moves its connection from its place to a WAIT on
  the request (`awaitAnswer`, `Server.waits`): out of the cap's count, never
  pushed out, under the request's own deadline (plus one sweep and two
  minutes, a bound only). One connection holds each request's wait - the
  last to present it; the one it leaves is CLOSED with 1013, never put back
  among the strangers: as the newest it would stand behind everybody who
  dialled after it, and `pair` frames alone would reorder the places until
  one new connection pushed out a later device. Whoever closes
  the request ends the wait (`endWait`): allowed lets the connection go,
  any other outcome puts it back as a newcomer with two fresh minutes; and
  a close landing between the store's `pending` and the wait taking hold is
  caught by reading the request again once it holds. The main `http.Server`
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
- `internal/server/pairing.go` — the device commands of contract §8A: `pair`
  and `pair.cancel` (the two allowed before a greeting), `device.approve`,
  `device.list`, `device.invite`, `device.revoke`, `identity.setLabel`
- `internal/server/requests.go` — who hears what about a request, and when:
  `device.pairRequested` to the issuing device's greeted connections (and
  again after each of its greetings), `pair.resolved` to the new device's
  connections that have not greeted, `device.pairResolved` to the issuer;
  and the sweeper (`Server.requestSweep`, 2 s) that closes what ran out
- `internal/server/gate.go` — the lock (047): the state on disk (no database
  and no key - a first password; both - locked; one without the other - no
  start), the service page's listener for the life of the process, `GET
  /health`, the password forms and `/control/state|unlock|password|backup`,
  and the ONE goroutine that serves the key file. `POST /control/link` is
  routed here too, so `noxd link` is held to the command rule in every state
  and told `state` (409) until the server is open. Every other request of the
  page goes to the open server's page once there is one; before that, the
  lock page and a 409 for anything posted
- `internal/server/lock_page.go` — the page while the server is not open: the
  password field and nothing else - no link, no address, no figure, no script
- `internal/server/backup.go` — a backup of the running server
- `internal/server/status.go`, `status_page.go`, `status_qr.go` — the OPEN
  server's service page, behind the gate on its loopback listener: the
  machine's state, the machine link with its countdown, `Add a device` / `New
  link` (`POST /link`), the address forms (`POST /addresses`) and `Change
  password` (posted to the gate); every form checked for `Host`, this page's
  `Origin` and the per-process form token, one token from the lock page to the
  open one (CSP `form-action 'self'`); the QR as SVG for the page and as text
  for `noxd link -qr`
- `internal/server/control.go` — `POST /control/link` on that same listener,
  the whole of `noxd link` but the printing, and the commands' side of the
  lock's `/control/*` (047): a local `Host`, `X-Nox-Control: 1` and NO
  `Origin`, or 403; a locked server answers `noxd link` with 409. The commands
  never open the database (invariant 1): they ask the running server
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
  nothing of it. Every byte is encrypted (047): a 32-byte header, then chunks
  of 64 KiB sealed one by one with ChaCha20-Poly1305 under a key of the file's
  own (HKDF of the data key and the id), nonce = the chunk's index, the index
  and "last" in the AAD. A chunk is sealed once all of it arrived - until then
  it waits in the request's memory - so a part holds whole chunks only, an
  upload continues from the start of the chunk it broke in, and a range opens
  only the chunks it touches (`Reader`, an `io.ReadSeeker` for ServeContent)
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
- Every test database and files directory is encrypted with a fixed test key
  (`testDataKey`), so a stack stopped and started again over the same files
  opens them. A server `Run` starts is locked like any other: `runServer` sets
  its first password - or enters it, on a restart - the way `noxd unlock`
  does, with keys sealed at cheap Argon2id costs (`testKDF`, through
  `run(..., kdf)`): what is under test around the lock is the lock. The
  production costs - and the time they take - are tested once, in
  `internal/vault`. `gate_test.go` holds the lock itself (the state on disk,
  the page and the commands in each state, a wrong password changing no byte),
  `at_rest_test.go` that no marker of a stopped server's data is left readable
  on its disk, and `TestNoPasswordAndNoKeyEverReachesTheLog` (`logs_test.go`)
  that neither a password nor the data key reaches the log.
- Nothing in the server runs tor, so no test needs one. `run_test.go` holds
  that `Run` starts no process even with a tor on the PATH and that the
  removed tor flags stop the start with a hint; `oneport_test.go` holds the
  one-port rules - every connection gets the slow-path timeouts and the idle
  timeout, a machine link or an invite through the onion service is like any
  other, access keys are gone from the wire; `channel_test.go` holds the entry's
  limits, this machine's share among them (a flood from it cuts only its own,
  loopback and the address a connection reached count as one) and a pipe
  listener whose connections report both of their ends; `unpaired_test.go`
  holds a stranger's deadline and cap, and that a stranger's connection ends
  with every answer but an upgrade - a body declared and never sent and
  net/http's own answers included - while a paired device's stays for the
  next request; it holds too that a pairing waiting for Allow outlives the
  deadline and the cap and is paired after, that the last connection to
  present a request holds its wait and the one before is closed - so repeats
  of `pair` on spare connections cannot reorder the places - and that a
  request ending without a pairing - Deny, Cancel, its time (the sweep, not
  the wait's own bound), or a close landing before the wait took hold
  (`beforeWait`) - makes the connection a stranger again; the addresses are
  `address_settings_test.go`, `status_addresses_test.go` and
  `internal/store/addresses_test.go`; the log
  is `logscrub_test.go` - the lock's own lines included - and
  `log_audit_test.go`, which drives a whole run - each start through the
  lock, parameters, `Set`, a machine link, an invite with its Allow, a refused
  upgrade through the onion service - and finds no onion address, link, token
  or key in it. The path
  through the real Tor network is checked by hand, with tor run as the
  separate service it is.
- Always `go test -race ./...`.

## Operational constraints

- Bind loopback in dev. The listener is TLS 1.3 and the channel check either
  way: there is no flag to serve plaintext or skip the check, and adding one
  would be adding the downgrade the whole design removed. The SERVICE PAGE is
  the deliberate exception and stays plain HTTP on its own loopback listener,
  together with `GET /health` and the `/control/*` the commands ask - `noxd
  link` for a machine link, `noxd unlock|password|backup` for the lock: the
  main port answers nothing before the check.
- **The server starts LOCKED (047).** Its data is encrypted with a data key only
  the owner's password unseals, and the password is stored nowhere: after every
  start only the service page listens, showing a password field and nothing
  else, and the main port is not even bound - a device sees what it sees when
  the server is off. The password goes in on the page or with `noxd unlock`
  (from a terminal without echo, or a line from standard input). Until it does
  there is no link to hand out, no address to set and nothing else running -
  the address watcher, the request sweeper, the stranger limits all start with
  the data; `GET /health` says `{"status":"locked"}`. A forgotten password is
  lost data, by decision. `-status-addr` cannot be empty, and a busy page port
  stops the start: the password has nowhere else to go.
- Backups: `noxd backup <absolute file>` - the RUNNING server snapshots the
  database (`VACUUM INTO` beside it, under the same key) and writes one tar with
  the sealed key and the finished attachments, never over an existing file and
  never as anything but `<file>.partial` until it is whole. `noxd restore <file>
  -db <path>` puts it onto an empty place with the same password, gives the
  journal a new id - every device re-reads the history, none pairs again - and
  names the devices the restored server lets in, with the moment the backup
  was made. Never copy a live DB; local filesystem only (WAL breaks on network
  mounts). tor's `HiddenServiceDir` is not in a backup: a server restored
  elsewhere without it gets a new onion address.
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
  `-onion-addr` or by `Set` on the open service page. With no child process
  there is nothing for a service manager to stop in order: a systemd unit
  needs no `KillMode` of its own.
- **Address flags** (045): `-public-addr` / `NOX_PUBLIC_ADDR` (`host:port`)
  and `-onion-addr` / `NOX_ONION_ADDR` (`<56>.onion`, `:443` allowed) write
  an address into the database only when the parameter appeared or changed
  since the value last applied (`*_address_param`), so an address set on the
  service page survives a restart with the old parameter still in the unit.
  They are applied once the password has opened the database, before the main
  port listens.
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
  header, and the main server is ordinarily bound to every interface. The
  address cannot be empty since 047: the password is entered there.
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
  derivative is a second copy of one fact. A page with no LIVE link - the lock
  page above all - carries no script and its policy admits none.
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
  cannot help. Its forms (`POST /link`, `POST /addresses` and the three
  password forms of 047) also need this page's own `Origin` and the per-process
  form token, which a page from elsewhere cannot read. `/control/*` turns the
  rule around - `X-Nox-Control: 1` and NO `Origin`: a browser always sends an
  `Origin` on a POST, and the custom header forces a CORS preflight nothing
  here answers, so a page from another site never gets as far as sending it,
  while `noxd link`, `noxd unlock`, `noxd password` and `noxd backup` send
  exactly that.
- **The listener's OWN address is verified after binding.** The config check
  catches a mistyped flag; a hostname can resolve to loopback at parse time and
  elsewhere at bind time, and only the socket knows which happened.
- **A busy status port STOPS the server (047).** It used to be logged and
  skipped, while the page held nothing a server needed; now the password that
  opens the data is entered there, and a server without its page could never
  open. 8081 is not a rare port - the error names it, and `-status-addr` moves
  it.
- **The database's pages carry no MAC (047).** Adiantum is length-preserving
  and deterministic: a page changed on disk is not detected, and two snapshots
  show which pages changed between them. Changing the disk needs the machine,
  which is out of scope; a backup - which does leave the machine - is closed by
  a MAC only the data key makes, and a restore checks it before anything moves.
  The `-shm` file is not encrypted: it is the WAL's index, page numbers and
  checksums, no data.
- **A wrong data key is told by the files, never by SQLite (047).** `db.Open`
  decrypts the first block of the database, of its WAL and of its rollback
  journal itself and refuses a key under which none of them shows its header,
  before SQLite opens anything. Leaving it to SQLite's "file is not a database"
  costs the WAL: SQLite runs its recovery first, reads every frame under that
  key as noise, and a connection closing alone over a WAL that looks empty
  deletes it. Any ONE of the three files is enough, never the database's
  alone: a crash in the middle of a checkpoint can tear the database's first
  block while the WAL still holds that page. An EMPTY database is not asked
  about at all, as SQLite does not ask: it deletes a WAL or a journal beside a
  database of zero pages unread, and a new database cut off in its first
  transaction is exactly an empty file beside a journal whose header has no
  magic yet - asking that journal refused the right key on every start.
- **A chunk cut back is sealed again under the same nonce.** Safe while the
  bytes are the same, which is what a client continuing an upload sends; other
  bytes under the same index could come only from a faulty device of the
  person's own, and both ciphertexts would show only to forensics on the
  machine's disk. Recorded in specs/047 research R11.
- **A restore lets in a device revoked after the backup (047).** Revocation
  deletes the device's row, the backup was made with it, and the restored
  server stays the same machine to every device it knew - pairing nobody again
  is the point of the restore. So nothing refuses such a device: `noxd restore`
  prints the backup's moment and every device it lets in, and says to revoke
  one revoked since again. A confirmation before unpacking, revocations kept
  outside the database and devices held back until approved were weighed and
  rejected (specs/047 research R11).
- **No limit on password attempts.** The page and the commands are loopback
  only, and whoever reaches them has the machine (out of scope). Each attempt
  costs Argon2id - about a second on a small board - and they are served one at
  a time.
- **A password is exactly what was typed:** at least twelve characters, not
  whitespace alone, never trimmed and never normalised. A password outside
  ASCII typed on a machine that composes Unicode differently is a different
  password.
- **A database without its key file, or a key file without its database, does
  not start** - the server never guesses which of the two is the mistake, and
  never creates a database beside a lost one. The error says what to do.
- **Only the TOKEN is stored, never the built link.** The page and `noxd link`
  rebuild the link from the unspent token whenever they are asked, and the
  address in it is resolved at that moment. A built link kept for later froze an
  address while "can a phone reach us" went on being recomputed, so a laptop
  whose network came up after the server did drew a QR over a link that still
  said 127.0.0.1. One fact, one record.
- **The machine link's address is NOT `listenAddress`.** That falls back to
  loopback under a wildcard bind, and the link is carried to ANOTHER device. It
  names the address another device can dial (`dialableHost`) - the bind when it
  names one, else the first interface that is up, IPv4 first - and falls back
  to loopback only when the machine has nothing else; a code is then drawn only
  when a public or onion address in the link still gives a phone a way in. An
  INVITE link takes the address the requesting device dialled instead (its
  `Host` header; through the onion service, where `Host` is the onion name, the
  head of the direct list - `inviteDirectAddress`): that device demonstrably
  reached the server there, while the machine link has no device asking yet.
  Both carry the stored public address first and the onion address last when
  they are set (045).
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
  of a device's round trips. A pairing through an invite is the one stranger
  that needs longer (046): Allow can take the invite's whole ten minutes, so
  while its request waits the connection it was presented on last holds a
  WAIT instead of a place - neither the deadline nor the cap applies to it -
  and the request's end puts it back as a newcomer or, allowed, lets it go.
  That keeps a bound: one connection per waiting request, and a request
  opens only with an invite a paired device issued and lives no longer than
  it. The connection a wait moves away from is closed rather than put back
  as the newest stranger, which would hand a key with a waiting request a
  way to reorder the places with `pair` frames alone; a request that ends
  without a pairing does put its connection back as the newest - once per
  request, worth one new connection to whoever ends it. What stays open:
  within its two minutes a
  stranger may send `pair` as often as it likes, each failed attempt one
  short write transaction on the single writer - and a stranger holding a
  leaked invite may hold its one waiting connection until the person answers
  or the invite's time runs out; and the connections past the
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
- **No migration for an older pre-release database**, and there will not be
  one: `001_init.sql` is edited in place, the schema check refuses a file
  written from another 001 (by the fingerprint of the migration text), and the
  cure is a new database and every device paired again.
- **No link and no token ever reaches the log.** The log is kept, copied and
  shipped, while a link is a way in for ten minutes - from anywhere, since it
  carries, packed, the onion service's key. The startup line, when no device
  can reach the machine, names the service page and `noxd link` - never a
  link. Issuing one logs who asked (`service page` or `noxd link`), a closed
  request logs its outcome, and nothing names a device, a token or an address
  in a link. Behind the call sites, every line goes through the log's own
  handler (`logscrub.go`), which turns any onion address into `[onion]` and
  any link into `[link]` whatever the text came from - a library's error
  quoting a Host header included. A machine link goes to the service page and
  to the terminal that ran `noxd link`, an invite to the device that asked for
  it, and neither goes anywhere else - which is why the page listens on
  loopback only and refuses to start anywhere else. TLS does NOT retire that
  reasoning: encryption stops somebody reading the link off the wire, and does
  nothing about a page that hands it to whoever asks. The loopback bind is what
  answers that, and `assertLoopback` checks the socket rather than the string
  somebody typed. Neither does a password or the data key (047): the lock logs
  that a password was accepted, refused or changed and that a backup was
  written, and never what was typed, what key it opened or where a backup went.
- **There is no revocation on the service page.** A lost device is revoked from
  a device the person holds - the one just added with a machine link included.
  The page hands out a way in; it does not judge which devices stay.
- `users.label` is neither unique nor validated (owner, 2026-09-02): a
  greeting may never be refused because of a name, since the client
  retries a refused greeting forever.
- No push, no `chat.markRead`, message `body` is open text — all gated
  by open questions; see contract §8 before touching.
- Cyrillic never appears in code, comments, or commit messages.
