package db

import (
	"context"
	"database/sql"
	"fmt"
	"io/fs"
	"sort"
	"strconv"
	"strings"
)

// Migrate applies append-only numbered *.sql files from fsys whose numeric
// prefix exceeds the database's PRAGMA user_version. Each file runs in one
// transaction together with the user_version bump. Returns the version the
// database ends at.
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
