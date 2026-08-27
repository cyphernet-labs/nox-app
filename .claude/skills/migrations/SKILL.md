---
name: migrations
description: Schema changes for this project's embedded SQLite database. Use this skill whenever the task involves creating or altering tables, columns, indexes, or constraints, adding a migration, or any mention of schema, DDL, ALTER TABLE, "new column", "new table", or changing what is stored — even if the user does not say the word "migration". Also consult it before modifying the migration runner in `internal/db`.
---

# Migrations

Migrations are append-only, numbered `.sql` files in `migrations/`,
embedded into the binary and applied at startup by `PRAGMA user_version`
(runner in `internal/db`). The migration history is the audited
schema record.

## Procedure

1. Find the highest existing prefix; create `migrations/NNN_short_name.sql`
   with the next zero-padded number. One concern per file.
2. Write plain DDL/DML. Every new table MUST be `STRICT` and should carry
   `CHECK` constraints for invariants the engine can enforce.
3. Never edit or delete a file that may have been applied anywhere (any
   deployed binary, any teammate's db). Fixing a past migration means
   writing a new one.
4. Update the corresponding queries in `internal/store` in the same change.
5. Test: run `go test ./...` (tests migrate a temp db from zero, so the
   full chain is exercised), and run the binary once against a copy of a
   real db file if one exists.

## Hard constraints of the runner (do not violate)

- Files are split on `;` at end-of-line (`splitStatements`). Therefore:
  NO statement may contain an internal `;` followed by a newline — this
  rules out `CREATE TRIGGER` bodies and multi-statement procedures. If a
  trigger becomes necessary, the runner must be upgraded first (in its
  own PR), not worked around.
- The `PRAGMA user_version` bump happens inside the same transaction as
  the file's statements; do not add your own BEGIN/COMMIT to migration
  files.

## SQLite specifics that bite

- `ALTER TABLE` supports ADD COLUMN and (3.35+) DROP COLUMN / RENAME.
  Anything structural beyond that (changing a type, adding a constraint
  to an existing table) requires the documented 12-step rebuild:
  create new table → copy → drop old → rename. Put ALL steps in one
  migration file, mindful of the `;` rule above (each statement on its
  own lines is fine; it is `;` **inside** one statement that is banned).
- New columns on existing tables need a `DEFAULT` or `NULL`-ability
  consistent with `STRICT`.
- `events` table: never ALTER its `seq` semantics; `AUTOINCREMENT` and
  the single writer are what make client replay correct (CLAUDE.md
  invariant 5).

## Checklist before finishing

- [ ] New file has the next number and was not renamed/renumbered
- [ ] All tables STRICT; constraints in the engine, not only in Go
- [ ] No `;` inside any single statement
- [ ] `internal/store` queries updated; `go test -race ./...` green
- [ ] No edit to any previously existing migration file
