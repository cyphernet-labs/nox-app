# CLAUDE.md — backend (Elixir / Phoenix)

Personal server: REST JSON API + Phoenix Channels over WebSockets,
embedded SQLite via exqlite (raw SQL, deliberately NO Ecto), single OS
process. Same architecture as the sibling Go project; the table in
README.md maps the concepts. Read this file fully before changing code —
the invariants are the architecture.

## Commands

    mix deps.get
    mix format                      # must leave no diff
    mix compile --warnings-as-errors
    mix test
    mix run --no-halt               # serve on http://127.0.0.1:4000
    iex -S mix                      # serve + live shell

## Architecture invariants (MUST hold after every change)

1. **Exactly one OS process opens the database file.** No sidecars, no
   cron, no second node.
2. **All writes go through `Backend.DB.Writer.transaction/1`** — the one
   GenServer owning the one write connection; its mailbox IS the write
   serialization. Never open a write connection anywhere else; never
   call `DB.execute`/`DB.query` with mutating SQL outside a
   `Writer.transaction` function.
3. **Writer transactions are milliseconds.** The Writer serializes ALL
   writes for the node: a slow function inside `transaction/1` blocks
   every other write. No network calls, no `Process.sleep`, no heavy
   computation inside; do not raise the GenServer.call timeout to
   "fix" a slow transaction — make the transaction fast.
4. **Transactional outbox.** Every mutation inserts its `events` row via
   `insert_event/4` in the SAME transaction; `push_event/1`
   (Endpoint.broadcast) runs only on `{:ok, ...}` AFTER commit. Never
   broadcast inside the transaction function; never mutate without an
   event.
5. **Replay contract** (`BackendWeb.EventsChannel`): the channel process
   is PubSub-subscribed when `join/3` returns; replay runs from its own
   `{:replay, last_seq}` message afterwards. Loss is impossible,
   duplicates at the boundary are expected, clients de-duplicate by
   `seq`. Preserve this order.
6. **`seq` is a strictly increasing total order** (single writer +
   AUTOINCREMENT). Never renumber or bulk-delete events in a way that
   breaks `last_seq` replay.
7. **Pragmas are fixed** in `Backend.DB.open/0` (WAL, busy_timeout=5000,
   synchronous=NORMAL, foreign_keys=ON) for every connection.
8. **Migrations are append-only** numbered files in `priv/migrations`,
   applied by `PRAGMA user_version` in `Writer.init/1` (before the
   endpoint starts). See the `migrations` skill before schema changes.
9. **Reads use `DB.with_read/1`** (fresh connection per call, closed
   after). Do not introduce a connection pool or cache connections in
   process state outside the Writer without discussion.
10. **exqlite is a NIF**: native C inside the VM. A memory fault there
    kills the whole node — supervision does not protect against it.
    Keep the native surface minimal: no additional NIFs without
    explicit justification.

## Code style

- Raw parameterized SQL (`?1, ?2 ...`) through `Backend.DB` only. No
  Ecto, no query builders, no interpolated SQL ever.
- Dependencies: exactly four (phoenix, bandit, jason, exqlite). Adding
  any requires written justification.
- `mix format` formatting; compile clean under `--warnings-as-errors`.
- Pattern matching and `with` chains over nested conditionals; contexts
  return `{:ok, _} | {:error, reason}`; controllers translate reasons to
  status codes and never leak internals.
- `@moduledoc` on every module states its role in the architecture.
- No macros beyond what Phoenix itself requires (`use Phoenix.*`). The
  audit trade for Phoenix is accepted; do not widen it.
- Web layer (`BackendWeb`) calls contexts (`Backend.*`); contexts do not
  call controllers. The one sanctioned exception is
  `Notes.push_event/1` calling `Endpoint.broadcast` (documented seam).

## File map

- `lib/backend/application.ex` — supervision tree; child ORDER matters
  (PubSub → Writer(+migrations) → Endpoint); do not reorder
- `lib/backend/db.ex`          — pragmas, query/execute helpers, with_read
- `lib/backend/db/writer.ex`   — THE single writer GenServer
- `lib/backend/db/migrator.ex` — user_version runner
- `lib/backend/notes.ex`       — context: reads, writes, outbox, broadcast
- `lib/backend_web/endpoint.ex`— socket mount, JSON parsing, router plug
- `lib/backend_web/router.ex`  — /api routes
- `lib/backend_web/controllers/note_controller.ex` — HTTP ↔ context
- `lib/backend_web/channels/`  — user_socket.ex (auth point),
  events_channel.ex (join + replay)
- `priv/migrations/`           — append-only numbered .sql

## Testing

- Each test opens its own temp db path (set `:backend, :db_path` in the
  test, or pass a path) and runs the Migrator from zero.
- Channel/controller tests: standard `Phoenix.ChannelTest` /
  `Phoenix.ConnTest` machinery is acceptable to add under `test/`.

## Operational constraints

- Loopback bind; Caddy terminates TLS. Before any exposure: set real
  `check_origin` origins and a generated `secret_key_base`
  (`config/config.exs` TODOs).
- Backups: `VACUUM INTO` off-machine or Litestream; never copy a live
  db; local filesystem only.
- Release: `MIX_ENV=prod mix release` (per-target); Burrito optional.

## Known deliberate omissions (do not "fix" silently)

- No authentication: intended shape is a token check in
  `UserSocket.connect/3` (Phoenix.Token) plus a plug in the `:api`
  pipeline. Ask before implementing differently.
- No outbox pruning (see the `channels-protocol` skill for the required
  resync policy first).
