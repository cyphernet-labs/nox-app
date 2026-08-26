package main

import (
	"database/sql"
	"embed"
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"strings"

	_ "modernc.org/sqlite"
)

//go:embed migrations/*.sql
var migrationsFS embed.FS

// Pragmas applied to every connection, per the reference configuration:
// WAL (readers concurrent with the writer), busy timeout (writer lock
// collisions wait instead of failing), NORMAL sync (safe in WAL),
// enforced foreign keys.
const pragmas = "?_pragma=busy_timeout(5000)" +
	"&_pragma=journal_mode(WAL)" +
	"&_pragma=synchronous(NORMAL)" +
	"&_pragma=foreign_keys(ON)"

// openDB returns two handles over the same file.
//
//	read:  a pool for concurrent SELECTs.
//	write: capped at exactly ONE connection; combined with _txlock=immediate,
//	       every write transaction is BEGIN IMMEDIATE on a single connection.
//	       This makes the single-writer rule structural: in-process
//	       SQLITE_BUSY between writers is unreachable.
func openDB(path string) (read, write *sql.DB, err error) {
	read, err = sql.Open("sqlite", "file:"+path+pragmas)
	if err != nil {
		return nil, nil, fmt.Errorf("open read handle: %w", err)
	}

	write, err = sql.Open("sqlite", "file:"+path+pragmas+"&_txlock=immediate")
	if err != nil {
		read.Close()
		return nil, nil, fmt.Errorf("open write handle: %w", err)
	}
	write.SetMaxOpenConns(1)

	if err = read.Ping(); err != nil {
		read.Close()
		write.Close()
		return nil, nil, fmt.Errorf("ping: %w", err)
	}
	return read, write, nil
}

var migNameRe = regexp.MustCompile(`^(\d+)_.*\.sql$`)

// migrate applies migrations/NNN_*.sql files, in order, whose numeric prefix
// is greater than PRAGMA user_version. Each file runs in one transaction;
// user_version is updated inside that same transaction. The schema history
// in the migrations directory is the audited artifact.
func migrate(write *sql.DB) error {
	var version int
	if err := write.QueryRow("PRAGMA user_version").Scan(&version); err != nil {
		return fmt.Errorf("read user_version: %w", err)
	}

	entries, err := migrationsFS.ReadDir("migrations")
	if err != nil {
		return err
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		names = append(names, e.Name())
	}
	sort.Strings(names)

	for _, name := range names {
		m := migNameRe.FindStringSubmatch(name)
		if m == nil {
			continue
		}
		n, _ := strconv.Atoi(m[1])
		if n <= version {
			continue
		}

		body, err := migrationsFS.ReadFile("migrations/" + name)
		if err != nil {
			return err
		}

		tx, err := write.Begin()
		if err != nil {
			return err
		}
		for _, stmt := range splitStatements(string(body)) {
			if _, err := tx.Exec(stmt); err != nil {
				tx.Rollback()
				return fmt.Errorf("migration %s: %w", name, err)
			}
		}
		// PRAGMA does not accept bound parameters; n comes from the
		// filename regexp, not from user input.
		if _, err := tx.Exec(fmt.Sprintf("PRAGMA user_version = %d", n)); err != nil {
			tx.Rollback()
			return err
		}
		if err := tx.Commit(); err != nil {
			return err
		}
		version = n
	}
	return nil
}

// splitStatements splits a migration file on ";" at end of line.
// Limitation (documented): statements containing ";\n" inside literals or
// trigger bodies are not supported; keep migration files to plain DDL/DML.
func splitStatements(s string) []string {
	parts := regexp.MustCompile(`;\s*\n`).Split(s, -1)
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		p = strings.TrimSuffix(p, ";")
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}
