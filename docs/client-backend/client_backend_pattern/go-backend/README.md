# personal-backend (Go)

Single-binary personal server: REST JSON API + push-only WebSocket,
embedded SQLite, no external services.

Architecture (as discussed):

- One OS process owns the SQLite file. WAL, busy_timeout=5000,
  synchronous=NORMAL, foreign_keys=ON on every connection. STRICT tables.
- Two `database/sql` handles over one file: a read pool for SELECTs and a
  write handle capped at ONE connection with `_txlock=immediate`
  (structural single writer; every write transaction is BEGIN IMMEDIATE).
- Transactional outbox: each mutation inserts an `events` row in the same
  transaction; after COMMIT the event goes to the in-process hub.
- Hub: one goroutine owns the subscriber map; register/unregister/broadcast
  are Go channels. No mutexes in the program.
- WebSocket `/ws?since=N`: subscribe first, then replay `seq > N`, then
  stream live. Clients de-duplicate by `seq`.
- Migrations: numbered `.sql` files embedded in the binary, applied by
  `PRAGMA user_version` at startup.

## Build and run

    go mod tidy
    go build -o server .
    ./server -addr 127.0.0.1:8080 -db app.db

Cross-compile (pure Go, no cgo): `GOOS=linux GOARCH=arm64 go build .`

## REST API

    GET    /api/notes             list
    GET    /api/notes/{id}        one
    POST   /api/notes             {"title": "...", "body": "..."}   -> 201
    PUT    /api/notes/{id}        {"title": "...", "body": "..."}
    DELETE /api/notes/{id}                                          -> 204
    GET    /api/events?since=N    outbox rows with seq > N (poll fallback)

Errors: `{"error": "..."}` with 400/404/500.

    curl -s localhost:8080/api/notes
    curl -s -X POST localhost:8080/api/notes \
         -H 'content-type: application/json' \
         -d '{"title":"first","body":"hello"}'

## WebSocket protocol

Connect: `GET /ws?since=<last seen seq, 0 initially>`. Server sends one
JSON text frame per event:

    {"seq":7,"type":"note.updated","entity":"note","entity_id":3,
     "payload":{...},"created_at":1723900000}

Rules for clients:
- persist the highest `seq` processed; reconnect with `?since=<it>`;
- ignore any frame with `seq <= last seen` (duplicates at the
  replay/live boundary are expected);
- on close, reconnect with backoff. Server pings every 30 s.

Try it: `npx wscat -c 'ws://127.0.0.1:8080/ws?since=0'`

## Operations

- TLS: keep the server on 127.0.0.1 and put Caddy in front:

      example.com {
          reverse_proxy 127.0.0.1:8080
      }

- systemd unit (sketch):

      [Service]
      ExecStart=/opt/backend/server -db /var/lib/backend/app.db
      Restart=always
      User=backend

- Backups: periodic `VACUUM INTO 'backup.db'` shipped off-machine, or
  Litestream for continuous replication. Never `cp` a live db. Test
  restores.
- Local filesystem only; WAL does not work over network filesystems.

## Next steps (deliberately omitted from boilerplate)

- Authentication (bearer token check in middleware + on `/ws`).
- Replace hand-written SQL in `store.go` with sqlc-generated code once
  the schema stabilizes (the SQL stays the audited artifact).
- Origin restriction in `ws.go` (`OriginPatterns`).
- Outbox pruning job (e.g. delete events older than N days) once clients
  are known to sync regularly.
