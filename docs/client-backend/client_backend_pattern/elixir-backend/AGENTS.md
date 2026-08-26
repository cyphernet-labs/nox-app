# AGENTS.md

Canonical agent instructions for this repository live in `CLAUDE.md` at
the repository root. Read it in full before making changes; workflow
playbooks live in `.claude/skills/`.

If your tool reads only this file, the five rules you must not break:

1. One OS process owns `app.db`; ALL writes go through
   `Backend.DB.Writer.transaction/1` (single GenServer, BEGIN
   IMMEDIATE). Keep transaction functions to milliseconds.
2. Every mutation inserts its `events` row in the same transaction;
   `Endpoint.broadcast` only after `{:ok, ...}`.
3. Raw parameterized SQL via `Backend.DB` only; no Ecto; no new
   dependencies without written justification.
4. Migrations are append-only numbered files in `priv/migrations`;
   never edit applied ones.
5. exqlite is a NIF — native crashes kill the node; add no further
   native code.
