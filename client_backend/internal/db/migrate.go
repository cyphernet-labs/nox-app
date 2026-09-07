package db

import (
	"context"
	"database/sql"
	"fmt"
	"hash/fnv"
	"io/fs"
	"sort"
	"strconv"
	"strings"
)

// Migrate applies append-only numbered *.sql files from fsys whose numeric
// prefix exceeds the database's PRAGMA user_version. Each file runs in one
// transaction together with the user_version bump. Returns the version the
// database ends at.
// Fingerprint is a stable hash of every migration file, recorded in the
// database when they are applied and compared on every start.
//
// It exists because of the pre-release rule: 001_init.sql is EDITED IN PLACE,
// while the runner keys on user_version and therefore skips a file it has
// already applied. So a database can carry a schema that no longer matches the
// code, and the mismatch surfaces far away as a raw "no such column" - the kind
// of error nobody can act on. A per-column allow-list catches that for columns
// somebody remembered to list; a fingerprint catches every column, index,
// CHECK and rename for free, and cannot be forgotten.
//
// FNV-1a, because it has to fit SQLite's 32-bit application_id and this is a
// change detector, not a security boundary.
func Fingerprint(fsys fs.FS) (int32, error) {
	names, err := fs.Glob(fsys, "*.sql")
	if err != nil {
		return 0, fmt.Errorf("list migrations: %w", err)
	}
	sort.Strings(names)

	h := fnv.New32a()
	for _, name := range names {
		raw, err := fs.ReadFile(fsys, name)
		if err != nil {
			return 0, fmt.Errorf("read migration %s: %w", name, err)
		}
		_, _ = h.Write([]byte(name))
		_, _ = h.Write(raw)
	}
	// int32 to match application_id's signed storage; the bit pattern survives.
	return int32(h.Sum32()), nil //nolint:gosec // deliberate 32-bit truncation
}

// RecordFingerprint stores the current one, so a later start can compare.
func RecordFingerprint(ctx context.Context, write *sql.DB, fingerprint int32) error {
	// PRAGMA does not take a parameter, and this value is our own hash.
	if _, err := write.ExecContext(ctx, fmt.Sprintf("PRAGMA application_id = %d", fingerprint)); err != nil {
		return fmt.Errorf("record schema fingerprint: %w", err)
	}
	return nil
}

// ReadFingerprint returns what the database was written with. Zero means a
// database from before fingerprints existed.
func ReadFingerprint(ctx context.Context, read *sql.DB) (int32, error) {
	var stored int32
	if err := read.QueryRowContext(ctx, "PRAGMA application_id").Scan(&stored); err != nil {
		return 0, fmt.Errorf("read schema fingerprint: %w", err)
	}
	return stored, nil
}

func Migrate(ctx context.Context, write *sql.DB, fsys fs.FS) (int, error) {
	var version int
	if err := write.QueryRowContext(ctx, "PRAGMA user_version").Scan(&version); err != nil {
		return 0, fmt.Errorf("read user_version: %w", err)
	}

	names, err := fs.Glob(fsys, "*.sql")
	if err != nil {
		return 0, fmt.Errorf("list migrations: %w", err)
	}
	sort.Strings(names)

	applied := false
	seen := make(map[int]string, len(names))
	for _, name := range names {
		num, err := migrationNumber(name)
		if err != nil {
			return 0, err
		}
		// A duplicate number below user_version would otherwise be skipped
		// silently, leaving one of the two files never applied.
		if prev, dup := seen[num]; dup {
			return 0, fmt.Errorf("migration %s: number %d already used by %s", name, num, prev)
		}
		seen[num] = name
		if num <= version {
			continue
		}
		if num != version+1 {
			return 0, fmt.Errorf("migration %s: expected number %d after version %d", name, version+1, version)
		}
		raw, err := fs.ReadFile(fsys, name)
		if err != nil {
			return 0, fmt.Errorf("read migration %s: %w", name, err)
		}
		if err := applyMigration(ctx, write, string(raw), num); err != nil {
			return 0, fmt.Errorf("apply migration %s: %w", name, err)
		}
		version = num
		applied = true
	}
	// Recorded ONLY when something was applied. Writing it on every run would
	// overwrite a stale value with the current one before anybody could compare
	// them - which is the whole reason the fingerprint exists.
	if applied {
		fingerprint, err := Fingerprint(fsys)
		if err != nil {
			return 0, err
		}
		if err := RecordFingerprint(ctx, write, fingerprint); err != nil {
			return 0, err
		}
	}
	return version, nil
}

func migrationNumber(name string) (int, error) {
	prefix, _, ok := strings.Cut(name, "_")
	if !ok {
		return 0, fmt.Errorf("migration %s: name must be NNN_description.sql", name)
	}
	num, err := strconv.Atoi(prefix)
	if err != nil {
		return 0, fmt.Errorf("migration %s: numeric prefix: %w", name, err)
	}
	return num, nil
}

func applyMigration(ctx context.Context, write *sql.DB, script string, num int) error {
	tx, err := write.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	for _, stmt := range splitStatements(script) {
		if _, err := tx.ExecContext(ctx, stmt); err != nil {
			return fmt.Errorf("exec %q: %w", firstLine(stmt), err)
		}
	}
	// PRAGMA values cannot be bound as parameters; num is an int under our control.
	if _, err := tx.ExecContext(ctx, fmt.Sprintf("PRAGMA user_version = %d", num)); err != nil {
		return fmt.Errorf("bump user_version: %w", err)
	}
	return tx.Commit()
}

// splitStatements cuts a migration file on `;` at end-of-line. Statements
// therefore must not contain an internal `;` followed by a newline (see the
// migrations skill; rules out CREATE TRIGGER bodies until the runner grows).
func splitStatements(script string) []string {
	var stmts []string
	var b strings.Builder
	for line := range strings.Lines(script) {
		b.WriteString(line)
		if strings.HasSuffix(strings.TrimRight(line, " \t\r\n"), ";") {
			stmt := strings.TrimSpace(b.String())
			if stmt != "" && stmt != ";" {
				stmts = append(stmts, stmt)
			}
			b.Reset()
		}
	}
	if tail := strings.TrimSpace(b.String()); tail != "" {
		stmts = append(stmts, tail)
	}
	return stmts
}

func firstLine(s string) string {
	line, _, _ := strings.Cut(strings.TrimSpace(s), "\n")
	return line
}
