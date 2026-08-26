# backend (Elixir / Phoenix)

Same system as the Go project, same architecture, expressed in OTP terms:

| Concept (as discussed)   | Go project                        | This project                          |
|--------------------------|-----------------------------------|---------------------------------------|
| Single writer            | write handle, MaxOpenConns(1)     | `Backend.DB.Writer` GenServer          |
| BEGIN IMMEDIATE writes   | `_txlock=immediate`               | explicit in `Writer.transaction/1`     |
| Read concurrency (WAL)   | read pool                         | per-call read connection (`DB.with_read`) |
| Hub / fan-out            | hand-written `hub.go`             | Phoenix PubSub + Channels (framework)  |
| WebSocket layer          | hand-written `ws.go`              | `socket "/ws"` + 2 small modules       |
| Outbox + replay by seq   | `events` table, `?since=N`        | same table, join param `last_seq`      |
| Migrations               | embedded `.sql` by `user_version` | `priv/migrations` by `user_version`    |

SQL is raw and parameterized via exqlite (no Ecto): the SQL on the page is
the SQL executed.

## Run

    mix deps.get
    mix run --no-halt        # or: iex -S mix

Listens on http://127.0.0.1:4000.

## REST API

Identical shape to the Go project:

    GET    /api/notes
    GET    /api/notes/:id
    POST   /api/notes           {"title": "...", "body": "..."}  -> 201
    PUT    /api/notes/:id       {"title": "...", "body": "..."}
    DELETE /api/notes/:id                                        -> 204
    GET    /api/events?since=N

    curl -s localhost:4000/api/notes
    curl -s -X POST localhost:4000/api/notes \
         -H 'content-type: application/json' \
         -d '{"title":"first","body":"hello"}'

## WebSocket (Phoenix Channels protocol)

Endpoint: `ws://127.0.0.1:4000/ws/websocket?vsn=2.0.0`. Wire format is the
Phoenix Channels v2 JSON array `[join_ref, ref, topic, event, payload]`;
heartbeats and reconnection are handled by the client libraries.

JavaScript (npm package `phoenix` — the first-party client):

    import { Socket } from "phoenix"

    const socket = new Socket("ws://127.0.0.1:4000/ws")
    socket.connect()

    let lastSeq = Number(localStorage.getItem("last_seq") || 0)
    const channel = socket.channel("events:all", { last_seq: lastSeq })

    channel.on("event", (ev) => {
      if (ev.seq <= lastSeq) return        // de-duplicate by seq
      lastSeq = ev.seq
      localStorage.setItem("last_seq", String(lastSeq))
      console.log(ev.type, ev.payload)
    })

    channel.join()

Flutter/Dart: package `phoenix_socket` (community-maintained
implementation of the same wire format); Swift: `SwiftPhoenixClient`;
Kotlin: `JavaPhoenixClient`. Verify maintenance status before committing —
only the JavaScript client is maintained by the Phoenix team itself.

Event frame payload (identical to the Go project):

    {"seq":7,"type":"note.updated","entity":"note","entity_id":3,
     "payload":{...},"created_at":1723900000}

## Operations

- TLS: keep the endpoint on 127.0.0.1, put Caddy in front (same Caddyfile
  as the Go project). Set real `check_origin` values and a generated
  `secret_key_base` (config/config.exs) before exposing.
- Release: `MIX_ENV=prod mix release` produces a self-contained directory
  bundling the Erlang runtime; built per target OS/arch. Optional: Burrito
  wraps it into a single executable.
- Backups: identical to the Go project — `VACUUM INTO` shipped
  off-machine or Litestream; never `cp` a live db; local filesystem only.

## Known trade-offs (as discussed in the design conversation)

- exqlite is a NIF: a memory fault in the native SQLite code terminates
  the whole BEAM node — the supervision tree does not protect against
  native crashes. This is the accepted cost of embedded SQLite on the
  BEAM.
- `use Phoenix.Endpoint` / `use Phoenix.Channel` inject framework code at
  compile time; the source on the page is smaller than the behavior that
  executes. That is the audit-surface trade accepted in exchange for the
  finished Channels layer and its four-platform client libraries.
