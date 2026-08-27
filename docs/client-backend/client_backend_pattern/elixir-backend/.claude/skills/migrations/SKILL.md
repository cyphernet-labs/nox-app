---
name: migrations
description: Schema changes for this project's embedded SQLite database. Use this skill whenever the task involves creating or altering tables, columns, indexes, or constraints, adding a migration, or any mention of schema, DDL, ALTER TABLE, "new column", "new table", or changing what is stored — even if the user does not say the word "migration". Also consult it before modifying Backend.DB.Migrator.
---

# Migrations

Append-only, numbered `.sql` files in `priv/migrations/`, applied at
node start by `Backend.DB.Migrator` (called from `Writer.init/1`, so the
schema is current before the endpoint serves). Version tracking:
`PRAGMA user_version`. The migration history is the audited schema
record. The sibling Go project uses the identical mechanism; keep the
schema files literally identical if both backends are maintained.

## Procedure

1. Next zero-padded number: `priv/migrations/NNN_short_name.sql`. One
   concern per file.
2. Plain DDL/DML. Every new table MUST be `STRICT` with `CHECK`
   constraints for engine-enforceable invariants.
3. Never edit or delete a file that may have been applied anywhere.
   Fixing a past migration means writing a new one.
4. Update the SQL in `Backend.Notes` (or the relevant context) in the
   same change.
5. Test from zero: delete/point to a fresh temp db and run
   `mix test` / `mix run --no-halt` once.

## Hard constraints of the runner (do not violate)

- Files are split on `;` at end-of-line. NO single statement may contain
  an internal `;` followed by a newline — this rules out
  `CREATE TRIGGER` bodies. If a trigger becomes necessary, upgrade the
  Migrator first (own change), never work around the splitter.
- The Migrator wraps each file plus the `user_version` bump in one
  `BEGIN IMMEDIATE`; do not put BEGIN/COMMIT inside migration files.
- Files ship inside the release via `priv/`; do not move the directory
  (`Application.app_dir(:backend, "priv/migrations")` must keep
  resolving).

## SQLite specifics that bite

- `ALTER TABLE`: ADD COLUMN and (3.35+) DROP COLUMN / RENAME only.
  Structural changes require the create-new → copy → drop-old → rename
  rebuild, all steps in ONE migration file (each statement may span
  lines; only `;` inside a statement is banned).
- New columns on existing tables need DEFAULT or NULL-ability consistent
  with `STRICT`.
- `events`: never alter `seq` semantics — AUTOINCREMENT plus the single
  Writer is what makes client replay correct (CLAUDE.md invariant 6).

## Checklist before finishing

- [ ] Next number; no renames of existing files
- [ ] STRICT tables; constraints in the engine, not only in Elixir
- [ ] No `;` inside any single statement
- [ ] Context SQL updated; `mix compile --warnings-as-errors` and
      `mix test` green from a fresh database
- [ ] No edit to any previously existing migration file
