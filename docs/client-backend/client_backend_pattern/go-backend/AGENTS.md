# AGENTS.md

Canonical agent instructions for this repository live in `CLAUDE.md` at
the repository root. Read it in full before making changes; workflow
playbooks live in `.claude/skills/`.

If your tool reads only this file, the five rules you must not break:

1. One OS process owns `app.db`; all writes go through the single write
   handle in `store.go` (`MaxOpenConns(1)`, `BEGIN IMMEDIATE`).
2. Every mutation inserts its `events` row in the same transaction;
   broadcast only after commit.
3. No mutexes: the hub goroutine owns all shared state via channels.
4. Migrations are append-only numbered files; never edit applied ones.
5. Raw parameterized SQL only; no ORM; no new dependencies without
   written justification.
